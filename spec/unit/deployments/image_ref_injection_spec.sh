Describe "deployments digest-pinned ref injection (--image-ref)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/yaml.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/_image_ref.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/k8s.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/helm.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/compose.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/ssh.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/gitops.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  PINNED="registry.release/app@${DIGEST}"

  BeforeEach 'mock.setup'
  AfterEach 'mock.cleanup'

  # =========================================================================
  # helm: --set image.repository/digest, tag cleared
  # =========================================================================
  Describe "deploy.helm.run --image-ref"
    It "sets image.repository and image.digest and clears the tag"
      helm_inject() {
        mock.create_echo "helm"
        mock.activate
        deploy.helm.run --chart mychart --image-ref "$PINNED"
      }
      When call helm_inject
      The status should be success
      The output should include "image.repository=registry.release/app"
      The output should include "image.digest=${DIGEST}"
      The output should include "image.tag="
      The stderr should include "running"
    End

    It "rejects a non-digest-pinned ref"
      helm_bad() {
        mock.create_echo "helm"
        mock.activate
        deploy.helm.run --chart mychart --image-ref "registry.release/app:v1"
      }
      When call helm_bad
      The status should equal 2
      The stderr should include "digest-pinned"
    End
  End

  # =========================================================================
  # k8s: staged manifest pinned, original untouched
  # =========================================================================
  Describe "deploy.k8s.run --image-ref"
    write_manifest() {
      K8S_MAN="$(mktemp -t brik-man.XXXXXX)"
      cat > "$K8S_MAN" <<'YAML'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/app:oldtag
YAML
    }
    cleanup_manifest() { rm -f "$K8S_MAN"; }
    Before 'write_manifest'
    After 'cleanup_manifest'

    It "applies a staged manifest with the image digest-pinned"
      k8s_inject() {
        # kubectl mock prints the file it is told to apply.
        mock.create_script "kubectl" '[ "$1" = "apply" ] && cat "$3"'
        mock.activate
        deploy.k8s.run --manifest "$K8S_MAN" --image-ref "$PINNED"
      }
      When call k8s_inject
      The status should be success
      The output should include "@${DIGEST}"
      The stderr should include "completed"
    End

    It "leaves the original manifest on disk untouched"
      k8s_untouched() {
        mock.create_script "kubectl" '[ "$1" = "apply" ] && cat "$3"'
        mock.activate
        deploy.k8s.run --manifest "$K8S_MAN" --image-ref "$PINNED" >/dev/null 2>&1
        grep -c "oldtag" "$K8S_MAN"
      }
      When call k8s_untouched
      The output should equal "1"
    End
  End

  # =========================================================================
  # compose: IMAGE_REF exported for variable substitution
  # =========================================================================
  Describe "deploy.compose.run --image-ref"
    It "exports IMAGE_REF as the pinned ref"
      compose_inject() {
        unset BRIK_DRY_RUN
        # docker mock echoes the IMAGE_REF it sees in its environment.
        mock.create_script "docker" 'echo "IMAGE_REF=$IMAGE_REF"'
        mock.activate
        deploy.compose.run --namespace proj --file /tmp/none-compose.yml --image-ref "$PINNED"
      }
      When call compose_inject
      The status should be success
      The output should include "IMAGE_REF=${PINNED}"
      The stderr should include "completed"
    End
  End

  # =========================================================================
  # ssh: staged source synced with image pinned
  # =========================================================================
  Describe "deploy.ssh.run --image-ref"
    setup_src() {
      SSH_SRC="$(mktemp -d)"
      cat > "${SSH_SRC}/deploy.yml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/app:oldtag
YAML
    }
    cleanup_src() { rm -rf "$SSH_SRC"; }
    Before 'setup_src'
    After 'cleanup_src'

    It "rsyncs a staged tree with the image digest-pinned"
      ssh_inject() {
        unset BRIK_DRY_RUN SSH_PRIVATE_KEY
        mock.create "ssh"
        # rsync mock cats the *.yml in the staged source directory it receives.
        mock.create_script "rsync" '
          for a in "$@"; do
            case "$a" in
              */) base="${a%/}"; [ -d "$base" ] && find "$base" -name "*.yml" -exec cat {} + 2>/dev/null ;;
            esac
          done
          exit 0'
        mock.activate
        deploy.ssh.run --host h --path /srv --source "$SSH_SRC" --image-ref "$PINNED"
      }
      When call ssh_inject
      The status should be success
      The output should include "@${DIGEST}"
      The stderr should include "completed"
    End

    It "leaves the original source tree untouched"
      ssh_untouched() {
        unset BRIK_DRY_RUN SSH_PRIVATE_KEY
        mock.create "ssh"
        mock.create_script "rsync" 'exit 0'
        mock.activate
        deploy.ssh.run --host h --path /srv --source "$SSH_SRC" --image-ref "$PINNED" >/dev/null 2>&1
        grep -c "oldtag" "${SSH_SRC}/deploy.yml"
      }
      When call ssh_untouched
      The output should equal "1"
    End
  End

  # =========================================================================
  # gitops: deploy.gitops.run must forward --image-ref to push_manifests so the
  # digest-pinned ref reaches the config repo (regression: run() accepted only
  # --image-tag, dropping the CD digest -- caught by the live CD keystone).
  # =========================================================================
  Describe "deploy.gitops.run --image-ref"
    It "forwards the digest-pinned ref to push_manifests"
      gitops_forward() {
        # Stub the push so the test stays hermetic (no git); capture its args.
        deploy.gitops.push_manifests() { printf 'push: %s\n' "$*"; }
        deploy.gitops.run --repo "http://example/config.git" --path k8s \
            --source k8s --image-ref "$PINNED" 2>/dev/null
      }
      When call gitops_forward
      The status should be success
      The output should include "--image-ref ${PINNED}"
    End
  End
End
