# Apply a list of patches to the current source tree with `git apply`.
#
#   cmake -DPATCHES="a.patch;b.patch" -P apply_patches.cmake   (cwd = source tree)
#
# Used as a FetchContent PATCH_COMMAND. Patches that are already applied are
# skipped, so re-running the patch step on a re-populate is harmless. A patch
# that no longer applies (e.g. after an upstream version bump) fails the build.
#
# Implemented in CMake rather than `sh -c ...` so it also works on Windows.

find_package(Git REQUIRED QUIET)

foreach(p IN LISTS PATCHES)
    execute_process(COMMAND "${GIT_EXECUTABLE}" apply --reverse --check "${p}"
                    RESULT_VARIABLE already OUTPUT_QUIET ERROR_QUIET)
    if(already EQUAL 0)
        message(STATUS "Already applied: ${p}")
        continue()
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${p}" RESULT_VARIABLE rc)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "Failed to apply ${p}; rebase it onto the new upstream version")
    endif()
    message(STATUS "Applied: ${p}")
endforeach()
