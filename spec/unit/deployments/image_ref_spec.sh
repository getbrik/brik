Describe "deployments/_image_ref.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/_image_ref.sh"

  DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  HEX="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  # =========================================================================
  # deploy.image_ref.pinned
  # =========================================================================
  Describe "deploy.image_ref.pinned"
    It "builds a digest-pinned ref from a bare image and a sha256 digest"
      When call deploy.image_ref.pinned "registry.release/app" "$DIGEST"
      The output should equal "registry.release/app@${DIGEST}"
    End

    It "strips an existing :tag before pinning"
      When call deploy.image_ref.pinned "registry.release/app:v1.2.3" "$DIGEST"
      The output should equal "registry.release/app@${DIGEST}"
    End

    It "preserves a registry host:port while stripping the tag"
      When call deploy.image_ref.pinned "nexus.briklab.test:8082/brik/app:0.1.0" "$DIGEST"
      The output should equal "nexus.briklab.test:8082/brik/app@${DIGEST}"
    End

    It "strips an existing @digest before re-pinning"
      When call deploy.image_ref.pinned "registry.release/app@sha256:dead" "$DIGEST"
      The output should equal "registry.release/app@${DIGEST}"
    End

    It "normalizes a bare hex digest to sha256:<hex>"
      When call deploy.image_ref.pinned "registry.release/app" "$HEX"
      The output should equal "registry.release/app@${DIGEST}"
    End

    It "rejects a malformed digest (invalid_input)"
      When call deploy.image_ref.pinned "registry.release/app" "sha256:tooshort"
      The status should equal 2
      The stderr should include "digest"
    End

    It "rejects an empty image (invalid_input)"
      When call deploy.image_ref.pinned "" "$DIGEST"
      The status should equal 2
      The stderr should include "required"
    End

    It "rejects an empty digest (invalid_input)"
      When call deploy.image_ref.pinned "registry.release/app" ""
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # deploy.image_ref.is_pinned
  # =========================================================================
  Describe "deploy.image_ref.is_pinned"
    It "accepts a well-formed digest-pinned ref"
      When call deploy.image_ref.is_pinned "registry.release/app@${DIGEST}"
      The status should equal 0
    End

    It "accepts a ref with a registry host:port"
      When call deploy.image_ref.is_pinned "nexus.briklab.test:8082/brik/app@${DIGEST}"
      The status should equal 0
    End

    It "rejects a tag-only ref"
      When call deploy.image_ref.is_pinned "registry.release/app:v1.2.3"
      The status should equal 1
    End

    It "rejects a digest with the wrong length"
      When call deploy.image_ref.is_pinned "registry.release/app@sha256:abc"
      The status should equal 1
    End
  End
End
