# Patch libarchive's zstd read filter to accept large-window zstd streams.
#
# EVE-OS release images are published as .zst files compressed with
# `zstd --long=30` (1 GiB window) to stay under GitHub's 2 GiB asset limit.
# libzstd refuses to decode frames whose window exceeds 128 MiB
# (ZSTD_WINDOWLOG_LIMIT_DEFAULT = 27) unless the decoder raises
# ZSTD_d_windowLogMax, and libarchive (as of 3.8.x) never does. The result is
# "Frame requires too much memory for decoding" when flashing those images.
#
# This raises the limit to the maximum libzstd supports on the platform, which
# is the equivalent of `zstd -d --long=31` / `--memory=2048MB`.
#
# Run with `cmake -P` from the libarchive source directory (FetchContent
# PATCH_COMMAND working directory).

set(ZSTD_FILTER_FILE "${CMAKE_CURRENT_SOURCE_DIR}/libarchive/archive_read_support_filter_zstd.c")

if(NOT EXISTS "${ZSTD_FILTER_FILE}")
    message(FATAL_ERROR "libarchive zstd window patch: ${ZSTD_FILTER_FILE} not found")
endif()

file(READ "${ZSTD_FILTER_FILE}" CONTENT)

set(PATCH_MARKER "ZFLASH: allow large zstd windows")
string(FIND "${CONTENT}" "${PATCH_MARKER}" ALREADY_PATCHED)
if(ALREADY_PATCHED GREATER -1)
    message(STATUS "libarchive zstd window patch already applied")
    return()
endif()

set(ANCHOR "	self->data = state;\n\n	state->out_block_size = out_block_size;")
string(FIND "${CONTENT}" "${ANCHOR}" ANCHOR_POS)
if(ANCHOR_POS EQUAL -1)
    message(FATAL_ERROR "libarchive zstd window patch: anchor not found in ${ZSTD_FILTER_FILE}; "
                        "libarchive changed, update src/cmake/libarchive_zstd_window_patch.cmake")
endif()

set(INSERT "	/* ${PATCH_MARKER} (e.g. images made with zstd --long=30) */
	{
		ZSTD_bounds wl = ZSTD_dParam_getBounds(ZSTD_d_windowLogMax);
		if (!ZSTD_isError(wl.error))
			ZSTD_DCtx_setParameter(dstream, ZSTD_d_windowLogMax,
			    wl.upperBound);
	}

")

string(SUBSTRING "${CONTENT}" 0 ${ANCHOR_POS} BEFORE)
string(SUBSTRING "${CONTENT}" ${ANCHOR_POS} -1 AFTER)
file(WRITE "${ZSTD_FILTER_FILE}" "${BEFORE}${INSERT}${AFTER}")
message(STATUS "Patched libarchive zstd reader to allow large window sizes")
