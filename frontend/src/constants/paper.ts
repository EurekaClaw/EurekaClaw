/**
 * Prefix used in chat history to mark a rewrite request. Must stay in
 * sync with `eurekaclaw.ui.constants.REWRITE_MARKER_PREFIX` — both
 * sides build the full marker as `${PREFIX}"${question}"`.
 */
export const REWRITE_MARKER_PREFIX = '↻ Rewrite requested: ';
