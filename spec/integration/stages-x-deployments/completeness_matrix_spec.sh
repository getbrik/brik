#shellcheck shell=bash
# L2 completeness matrix: capability x deploy target.
#
# Executable form of the design matrix (cicd-decoupling design review,
# deliverable L2): every deploy capability must hold an EXPLICIT stance for
# every target. A new target (or a new capability) that forgets a cell fails
# here instead of surfacing as a silent runtime fallback -- the class of hole
# the 2026-06-10 audit found twice (compose read-back calling a function that
# did not exist, gitops absent from the rollout-strategy case).
#
# Target SoT: lib/deployments/*.sh minus internal helpers (_image_ref,
# readback) and controllers (argocd is gitops' controller, gated separately).

Describe "L2 completeness: capability x deploy target"
  DEPLOY_DIR="$BRIK_HOME/lib/deployments"
  STAGE_FILE="$BRIK_HOME/lib/stages/deploy.sh"
  READBACK_FILE="$BRIK_HOME/lib/deployments/readback.sh"

  deploy_targets() {
    local f base
    for f in "$DEPLOY_DIR"/*.sh; do
      base="$(basename "$f" .sh)"
      case "$base" in _image_ref|readback|argocd) continue ;; esac
      printf '%s\n' "$base"
    done | LC_ALL=C sort
  }

  # has_fn <module> <function> - source the module in a subshell and check
  # the function is defined (modules are side-effect free at top level).
  has_fn() {
    ( set +e
      # shellcheck source=/dev/null
      . "$DEPLOY_DIR/$1.sh" 2>/dev/null
      declare -f "$2" >/dev/null 2>&1 )
  }

  # case_labels <file> <anchor-substring> - print the labels of the first
  # `case "$target" in` that follows a line containing <anchor-substring>
  # (plain substring match: no regex escaping pitfalls), one per line,
  # `|` groups split, `*` excluded, sorted.
  case_labels() {
    awk -v anchor="$2" '
      index($0, anchor)          { armed = 1 }
      armed && /case "\$target" in/ { incase = 1; next }
      incase && /esac/           { exit }
      incase && /^[[:space:]]*[a-z0-9*|]+\)/ {
        lab = $0
        gsub(/[[:space:]]|\)/, "", lab)
        n = split(lab, parts, "|")
        for (i = 1; i <= n; i++) if (parts[i] != "*") print parts[i]
      }
    ' "$1" | LC_ALL=C sort
  }

  Describe "deploy primitive"
    missing_run() {
      local t
      for t in $(deploy_targets); do
        has_fn "$t" "deploy.${t}.run" || printf '%s ' "$t"
      done
      return 0
    }
    It "every target implements deploy.<target>.run"
      When call missing_run
      The output should equal ""
    End
  End

  Describe "digest read-back"
    # Declared exception: gitops read-back is delegated to its controller
    # (deploy.argocd.get_deployed_digest, gated below); the target module
    # itself carries no live query.
    missing_readback() {
      local t
      for t in $(deploy_targets); do
        [[ "$t" == "gitops" ]] && continue
        has_fn "$t" "deploy.${t}.get_deployed_digest" || printf '%s ' "$t"
      done
      return 0
    }
    It "every non-delegated target implements deploy.<target>.get_deployed_digest"
      When call missing_readback
      The output should equal ""
    End

    It "the gitops controller (argocd) implements get_deployed_digest"
      When call has_fn argocd deploy.argocd.get_deployed_digest
      The status should be success
    End

    It "readback._live declares a stance for every target (no silent fallback)"
      When call case_labels "$READBACK_FILE" '_deploy.readback._live()'
      The output should equal "$(deploy_targets)"
    End
  End

  Describe "rollout strategy"
    It "the strategy case declares a stance for every target (no silent fall-through)"
      When call case_labels "$STAGE_FILE" 'if [[ -n "$strategy" ]]'
      The output should equal "$(deploy_targets)"
    End
  End

  Describe "pinned image-ref wiring"
    missing_image_ref() {
      local t
      for t in $(deploy_targets); do
        grep -q -- '--image-ref' "$DEPLOY_DIR/$t.sh" || printf '%s ' "$t"
      done
      return 0
    }
    It "every target accepts --image-ref (digest-pinned deploys)"
      When call missing_image_ref
      The output should equal ""
    End
  End

  Describe "rollback"
    # Declared set: targets exposing a native rollback primitive. gitops rolls
    # back by reverting the config repo; push targets degrade to hold (logged
    # by _brik.deploy._on_failure). Extending rollback to a new target means
    # updating this declaration -- that is the point of the matrix.
    rollback_targets() {
      local t
      for t in $(deploy_targets); do
        has_fn "$t" "deploy.${t}.rollback" && printf '%s\n' "$t"
      done
      return 0
    }
    It "targets with a native rollback match the declared set (gitops)"
      When call rollback_targets
      The output should equal "gitops"
    End
  End
End
