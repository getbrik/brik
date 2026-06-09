Describe "deployments live digest read-back"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/_image_ref.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/k8s.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/compose.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/argocd.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/helm.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/ssh.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  PINNED="registry.release/app@${DIGEST}"

  BeforeEach 'mock.setup'
  AfterEach 'mock.cleanup'

  # =========================================================================
  # deploy.image_ref.extract_digest
  # =========================================================================
  Describe "deploy.image_ref.extract_digest"
    It "extracts the sha256 digest from a pinned ref"
      When call deploy.image_ref.extract_digest "$PINNED"
      The output should equal "$DIGEST"
    End

    It "returns unknown for a tag-only ref"
      When call deploy.image_ref.extract_digest "registry.release/app:v1.2.3"
      The output should equal "unknown"
    End
  End

  # =========================================================================
  # deploy.k8s.get_deployed_digest
  # =========================================================================
  Describe "deploy.k8s.get_deployed_digest"
    It "returns the digest of the running deployment image"
      k8s_digest() {
        mock.create_output "kubectl" "$PINNED" 0
        mock.activate
        deploy.k8s.get_deployed_digest --deployment app --namespace staging
      }
      When call k8s_digest
      The output should equal "$DIGEST"
    End

    It "returns unknown when the running image is tag-based"
      k8s_tag() {
        mock.create_output "kubectl" "registry.release/app:v1.2.3" 0
        mock.activate
        deploy.k8s.get_deployed_digest --deployment app --namespace staging
      }
      When call k8s_tag
      The output should equal "unknown"
    End

    It "fails external_fail (5) when kubectl errors"
      k8s_fail() {
        mock.create_exit "kubectl" 1
        mock.activate
        deploy.k8s.get_deployed_digest --deployment app --namespace staging
      }
      When call k8s_fail
      The status should equal 5
      The stderr should include "kubectl"
    End
  End

  # =========================================================================
  # deploy.compose.get_deployed_digest
  # =========================================================================
  Describe "deploy.compose.get_deployed_digest"
    It "returns the digest of the running container image"
      compose_digest() {
        mock.create_script "docker" '
          for a in "$@"; do [ "$a" = "ps" ] && { echo "cid123"; exit 0; }; done
          [ "$1" = "inspect" ] && echo "registry.release/app@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"'
        mock.activate
        deploy.compose.get_deployed_digest --service web --project proj
      }
      When call compose_digest
      The output should equal "$DIGEST"
    End

    It "returns unknown when no container is running"
      compose_none() {
        mock.create_script "docker" 'for a in "$@"; do [ "$a" = "ps" ] && exit 0; done'
        mock.activate
        deploy.compose.get_deployed_digest --service web --project proj
      }
      When call compose_none
      The output should equal "unknown"
    End
  End

  # =========================================================================
  # deploy.argocd.get_deployed_digest
  # =========================================================================
  Describe "deploy.argocd.get_deployed_digest"
    It "returns the digest from the app summary images"
      argocd_digest() {
        mock.create_script "argocd" '
          printf "%s" "{\"status\":{\"summary\":{\"images\":[\"registry.release/app@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"]}}}"'
        mock.activate
        deploy.argocd.get_deployed_digest --app app-staging
      }
      When call argocd_digest
      The output should equal "$DIGEST"
    End

    It "returns unknown when the app reports a tag-based image"
      argocd_tag() {
        mock.create_script "argocd" '
          printf "%s" "{\"status\":{\"summary\":{\"images\":[\"registry.release/app:v1.2.3\"]}}}"'
        mock.activate
        deploy.argocd.get_deployed_digest --app app-staging
      }
      When call argocd_tag
      The output should equal "unknown"
    End
  End

  # =========================================================================
  # deploy.helm.get_deployed_digest
  # =========================================================================
  Describe "deploy.helm.get_deployed_digest"
    It "returns the digest of the live release manifest"
      helm_digest() {
        mock.create_script "helm" '
cat <<YAML
apiVersion: apps/v1
kind: Service
metadata:
  name: app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.release/app@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
YAML'
        mock.activate
        deploy.helm.get_deployed_digest --release app --namespace staging
      }
      When call helm_digest
      The output should equal "$DIGEST"
    End

    It "returns unknown when the release image is tag-based"
      helm_tag() {
        mock.create_script "helm" '
cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.release/app:v1.2.3
YAML'
        mock.activate
        deploy.helm.get_deployed_digest --release app --namespace staging
      }
      When call helm_tag
      The output should equal "unknown"
    End

    It "returns 2 when --release is missing"
      When call deploy.helm.get_deployed_digest --namespace staging
      The status should equal 2
      The stderr should include "release name is required"
    End

    It "fails external_fail (5) when helm errors"
      helm_fail() {
        mock.create_exit "helm" 1
        mock.activate
        deploy.helm.get_deployed_digest --release app --namespace staging
      }
      When call helm_fail
      The status should equal 5
      The stderr should include "helm get manifest failed"
    End
  End

  # =========================================================================
  # deploy.ssh.get_deployed_digest
  # =========================================================================
  Describe "deploy.ssh.get_deployed_digest"
    It "reports unsupported (no live image query for rsync+restart)"
      When call deploy.ssh.get_deployed_digest
      The output should equal "unsupported"
      The status should be success
    End
  End
End
