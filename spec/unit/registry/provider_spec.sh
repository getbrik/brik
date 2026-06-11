#shellcheck shell=bash
# Contract for the provider manifest family (third registry family): one
# interchangeable implementation of a capability behind a testable contract.

Describe "registry.provider accessors"
  # Ensure the cache is built before the suite runs (idempotent if up to date).
  BeforeAll '! [[ -f "$BRIK_HOME/lib/registry/cache/registry.json" ]] && "$BRIK_HOME/scripts/compile-registry.sh" >/dev/null 2>&1; true'

  Include "$BRIK_HOME/lib/registry/registry.sh"

  Describe "registry.provider.list"
    It "returns the 6 builtin providers"
      When call registry.provider.list
      The status should be success
      The line 1 of stdout should equal "cosign-key"
      The line 2 of stdout should equal "cosign-keyless"
      The line 3 of stdout should equal "cosign-kms-openbao"
      The line 4 of stdout should equal "gitsign"
      The line 5 of stdout should equal "oras-transport"
      The line 6 of stdout should equal "ssh-signing"
    End
  End

  Describe "registry.provider.exists"
    It "succeeds for a builtin provider"
      When call registry.provider.exists ssh-signing
      The status should be success
    End

    It "fails (2) for an unknown provider"
      When call registry.provider.exists ghost-signing
      The status should equal 2
    End
  End

  Describe "registry.provider.capability"
    It "maps ssh-signing to evidence-commit-signing"
      When call registry.provider.capability ssh-signing
      The output should equal "evidence-commit-signing"
    End

    It "maps cosign-kms-openbao to artifact-attestation"
      When call registry.provider.capability cosign-kms-openbao
      The output should equal "artifact-attestation"
    End
  End

  Describe "registry.provider.binding"
    It "binds the signing providers through the referential"
      When call registry.provider.binding ssh-signing
      The output should equal "referential"
    End
  End

  Describe "registry.provider.contract"
    It "declares the versioned contract id"
      When call registry.provider.contract cosign-keyless
      The output should equal "artifact-attestation/v1"
    End
  End

  Describe "registry.provider.tools"
    It "derives the tool matrix entry for ssh-signing"
      When call registry.provider.tools ssh-signing
      The output should equal "ssh-keygen>=8.8"
    End

    It "pins the cosign minimum for the KMS provider"
      When call registry.provider.tools cosign-kms-openbao
      The output should equal "cosign>=3.0.6"
    End

    It "lists a tool without a version floor as a bare name"
      When call registry.provider.tools gitsign
      The output should equal "gitsign"
    End
  End

  Describe "registry.provider.for_capability"
    It "lists the three attestation providers"
      When call registry.provider.for_capability artifact-attestation
      The line 1 of stdout should equal "cosign-key"
      The line 2 of stdout should equal "cosign-keyless"
      The line 3 of stdout should equal "cosign-kms-openbao"
    End

    It "is empty (rc 0) for a capability with no provider"
      When call registry.provider.for_capability quantum-signing
      The status should be success
      The output should equal ""
    End
  End
End
