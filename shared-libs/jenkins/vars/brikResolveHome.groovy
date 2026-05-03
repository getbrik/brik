/**
 * brikResolveHome - Locate the Brik shared library on disk.
 *
 * Jenkins clones Global Libraries into ${WORKSPACE}@libs/<hash>/. This
 * helper scans that directory for the Brik repo (identified by a `lib/`
 * subdirectory) and returns its absolute path. Falls back to
 * ${WORKSPACE}@libs/brik when no candidate is found.
 *
 * Usage:
 *   def brikHome = brikResolveHome()
 */
def call() {
    return sh(
        script: '''#!/bin/bash
            libs_dir="${WORKSPACE}@libs"
            if [ -d "$libs_dir" ]; then
                for d in "$libs_dir"/*/; do
                    if [ -d "${d}lib" ]; then
                        printf '%s' "${d%/}"
                        exit 0
                    fi
                done
            fi
            printf '%s' "${libs_dir}/brik"
        ''',
        returnStdout: true
    ).trim()
}
