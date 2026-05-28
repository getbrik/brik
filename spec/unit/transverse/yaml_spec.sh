Describe "yaml.sh (transverse YAML merge/patch helper)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/yaml.sh"

  # Per-test tempdir so fixtures don't collide across parallel workers.
  setup_tmp() {
    _YAML_TMP="$(mktemp -d)"
  }
  teardown_tmp() {
    [[ -n "${_YAML_TMP:-}" && -d "$_YAML_TMP" ]] && rm -rf "$_YAML_TMP"
  }

  Describe "transverse.yaml.merge"
    Before 'setup_tmp'
    After 'teardown_tmp'

    It "deep-merges two YAML files with override winning and writes to --output"
      write_fixtures() {
        printf 'app:\n  image: nginx\n  tag: v1\nreplicas: 1\n' > "${_YAML_TMP}/base.yml"
        printf 'replicas: 3\napp:\n  tag: v2\n'                 > "${_YAML_TMP}/override.yml"
      }
      write_fixtures

      When call transverse.yaml.merge \
          "${_YAML_TMP}/base.yml" \
          "${_YAML_TMP}/override.yml" \
          --output "${_YAML_TMP}/merged.yml"
      The status should be success
      The contents of file "${_YAML_TMP}/merged.yml" should include "replicas: 3"
      The contents of file "${_YAML_TMP}/merged.yml" should include "image: nginx"
      The contents of file "${_YAML_TMP}/merged.yml" should include "tag: v2"
    End

    It "writes merged YAML to stdout when --output is omitted"
      write_fixtures_stdout() {
        printf 'a: 1\nb: 2\n' > "${_YAML_TMP}/base.yml"
        printf 'b: 20\n'       > "${_YAML_TMP}/override.yml"
      }
      write_fixtures_stdout

      When call transverse.yaml.merge "${_YAML_TMP}/base.yml" "${_YAML_TMP}/override.yml"
      The status should be success
      The output should include "b: 20"
      The output should include "a: 1"
    End

    It "fails when base file is missing"
      When call transverse.yaml.merge "/nonexistent.yml" "/also-missing.yml"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "not found"
    End

    It "fails when base argument is empty"
      When call transverse.yaml.merge "" ""
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "required"
    End
  End

  Describe "transverse.yaml.patch"
    Before 'setup_tmp'
    After 'teardown_tmp'

    It "sets a scalar value at the given path in place"
      write_fixture() {
        printf 'spec:\n  replicas: 1\n' > "${_YAML_TMP}/file.yml"
      }
      write_fixture

      When call transverse.yaml.patch "${_YAML_TMP}/file.yml" ".spec.replicas" "5"
      The status should be success
      # Values are quoted as strings (mirrors existing gitops.render_manifests behavior).
      The contents of file "${_YAML_TMP}/file.yml" should include 'replicas: "5"'
    End

    It "writes patched YAML to --output when provided, leaving source untouched"
      write_fixture_out() {
        printf 'key: original\n' > "${_YAML_TMP}/src.yml"
      }
      write_fixture_out

      When call transverse.yaml.patch "${_YAML_TMP}/src.yml" ".key" "new" --output "${_YAML_TMP}/dst.yml"
      The status should be success
      The contents of file "${_YAML_TMP}/dst.yml" should include "key: new"
      The contents of file "${_YAML_TMP}/src.yml" should include "key: original"
    End

    It "fails when path is missing"
      printf 'a: 1\n' > "${_YAML_TMP}/file.yml"
      When call transverse.yaml.patch "${_YAML_TMP}/file.yml" "" "value"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "path"
    End

    It "fails when file does not exist"
      When call transverse.yaml.patch "${_YAML_TMP}/missing.yml" ".a" "1"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "not found"
    End
  End

  Describe "transverse.yaml.set_image_tag"
    Before 'setup_tmp'
    After 'teardown_tmp'

    It "rewrites the image tag suffix at the given path in place"
      write_deploy() {
        cat > "${_YAML_TMP}/deploy.yml" <<'YAML'
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
      write_deploy

      When call transverse.yaml.set_image_tag \
          "${_YAML_TMP}/deploy.yml" \
          ".spec.template.spec.containers[]?.image" \
          "newtag"
      The status should be success
      The contents of file "${_YAML_TMP}/deploy.yml" should include "registry.example.com/app:newtag"
      The contents of file "${_YAML_TMP}/deploy.yml" should not include ":oldtag"
    End

    It "leaves the source untouched and writes to --output when provided"
      write_deploy_out() {
        cat > "${_YAML_TMP}/deploy.yml" <<'YAML'
spec:
  template:
    spec:
      containers:
        - name: app
          image: myimage:v1
YAML
      }
      write_deploy_out

      When call transverse.yaml.set_image_tag \
          "${_YAML_TMP}/deploy.yml" \
          ".spec.template.spec.containers[]?.image" \
          "v2" \
          --output "${_YAML_TMP}/out.yml"
      The status should be success
      The contents of file "${_YAML_TMP}/out.yml" should include "myimage:v2"
      The contents of file "${_YAML_TMP}/deploy.yml" should include "myimage:v1"
    End

    It "fails when tag is missing"
      printf 'dummy: ok\n' > "${_YAML_TMP}/file.yml"
      When call transverse.yaml.set_image_tag "${_YAML_TMP}/file.yml" ".spec.template.spec.containers[]?.image" ""
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "tag"
    End
  End

  Describe "error paths - option and positional validation"
    Before 'setup_tmp'
    After 'teardown_tmp'

    It "merge rejects unknown option"
      When call transverse.yaml.merge --nosuch value
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End

    It "merge rejects a 3rd positional argument"
      printf 'a: 1\n' > "${_YAML_TMP}/a.yml"
      printf 'b: 2\n' > "${_YAML_TMP}/b.yml"
      When call transverse.yaml.merge "${_YAML_TMP}/a.yml" "${_YAML_TMP}/b.yml" "${_YAML_TMP}/c.yml"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unexpected positional"
    End

    It "merge fails when override file is missing"
      printf 'a: 1\n' > "${_YAML_TMP}/a.yml"
      When call transverse.yaml.merge "${_YAML_TMP}/a.yml" "${_YAML_TMP}/missing.yml"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "override file not found"
    End

    It "patch rejects unknown option"
      When call transverse.yaml.patch --nosuch file
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End

    It "patch rejects a 4th positional argument"
      printf 'a: 1\n' > "${_YAML_TMP}/file.yml"
      When call transverse.yaml.patch "${_YAML_TMP}/file.yml" ".a" "2" "extra"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unexpected positional"
    End

    It "patch fails when file arg is empty"
      When call transverse.yaml.patch "" ".a" "1"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "file is required"
    End

    It "set_image_tag rejects unknown option"
      When call transverse.yaml.set_image_tag --nosuch file
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End

    It "set_image_tag rejects a 4th positional argument"
      printf 'spec: {}\n' > "${_YAML_TMP}/file.yml"
      When call transverse.yaml.set_image_tag "${_YAML_TMP}/file.yml" ".img" "v1" "extra"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unexpected positional"
    End

    It "set_image_tag fails when file does not exist"
      When call transverse.yaml.set_image_tag "${_YAML_TMP}/missing.yml" ".img" "v1"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "not found"
    End

    It "patch fails when path arg is empty but no extra value"
      printf 'a: 1\n' > "${_YAML_TMP}/file.yml"
      When call transverse.yaml.patch "${_YAML_TMP}/file.yml" ""
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "path is required"
    End

    It "merge fails when second positional arg is empty"
      When call transverse.yaml.merge "" ""
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "required"
    End
  End
End
