/**
 * brikResolveHome - Locate the Brik shared library on disk.
 *
 * Jenkins clones Global Libraries into ${WORKSPACE}@libs/<hash>/. This
 * helper scans that directory for the Brik repo and returns its absolute
 * path.
 *
 * Matching criterion: a hash-named directory is the Brik library when it
 * contains vars/brikPipeline.groovy. This is a strict invariant -- if
 * Jenkins is currently running brikPipeline(), then that file MUST exist
 * in one of the hash-named clones under @libs/. Earlier revisions checked
 * for lib/, which is a weaker marker that can be absent from shallow clones.
 *
 * Cold-cache race: on the very first build after a workspace cleanup,
 * the SCM clone of the library may not have finished writing to disk by
 * the time this helper runs. Poll for up to 5 seconds before failing.
 *
 * On exhaustion: exit 1 with a diagnostic on stderr instead of returning
 * a fake path. The previous "${libs_dir}/brik" fallback only pushed the
 * crash one step later, with a cryptic "No such file or directory" on
 * jenkins-wrapper.sh that masked the real cause.
 *
 * Usage:
 *   def brikHome = brikResolveHome()
 */
def call() {
    return sh(
        script: '''#!/bin/bash
            set -eu
            libs_dir="${WORKSPACE}@libs"
            attempts=0
            max_attempts=10   # 10 * 0.5s = 5s max
            while [ "$attempts" -lt "$max_attempts" ]; do
                if [ -d "$libs_dir" ]; then
                    for d in "$libs_dir"/*/; do
                        if [ -f "${d}vars/brikPipeline.groovy" ]; then
                            printf '%s' "${d%/}"
                            exit 0
                        fi
                    done
                fi
                attempts=$((attempts + 1))
                sleep 0.5
            done

            ls -la "$libs_dir" >&2 2>/dev/null || printf '[brik] %s: @libs/ not present\\n' "$libs_dir" >&2
            printf '[brik] brikResolveHome: could not locate the Brik shared library under %s/ after %d attempts (5s). Check that @Library(\\'brik\\') is declared in the Jenkinsfile and that the SCM clone of the library completed.\\n' "$libs_dir" "$max_attempts" >&2
            exit 1
        ''',
        returnStdout: true
    ).trim()
}
