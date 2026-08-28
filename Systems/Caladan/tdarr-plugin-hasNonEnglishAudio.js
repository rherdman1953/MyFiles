"use strict";
// Tdarr Local Flow Plugin: Has Non-English Audio
// Version: 1.1.0
//
// PURPOSE:
//   Gate plugin that checks ffProbeData.streams for audio tracks with
//   languages NOT in the configured keep list. Routes to Output 1 if
//   non-kept audio exists AND at least one kept track is present (safe
//   to proceed with removal). Routes to Output 2 if all audio is already
//   in the keep list, no audio exists, or no kept tracks found (safety
//   guard to prevent silent files).
//
// INSTALL:
//   Copy to:
//   /mnt/user/appdata/tdarr/server/Tdarr/Plugins/FlowPlugins/LocalFlowPlugins/audio/hasNonEnglishAudio/1.0.0/index.js
//   Then click "Sync node plugins" in Tdarr Flows page.
//
// FLOW POSITION:
//   Input File → [This Plugin] → (Output 1) → Begin Command → ...
//                              → (Output 2) → [unconnected / exit as Not Required]

Object.defineProperty(exports, "__esModule", { value: true });
exports.plugin = exports.details = void 0;

var details = function () { return ({
  name: 'Has Non-English Audio',
  description: 'Checks ffProbeData for audio tracks with languages not in the keep list. '
    + 'Output 1: non-kept audio found AND at least one kept track exists - proceed to removal. '
    + 'Output 2: all audio already in keep list, no audio streams, or no kept tracks found (safety guard).',
  style: { borderColor: 'orange' },
  tags: 'audio',
  isStartPlugin: false,
  pType: '',
  requiresVersion: '2.11.01',
  sidebarPosition: -1,
  icon: 'faQuestion',
  inputs: [
    {
      label: 'Languages To Keep',
      name: 'languages_to_keep',
      type: 'string',
      defaultValue: 'eng,spa,und',
      inputUI: { type: 'text' },
      tooltip: 'Comma-separated ISO 639-2 language codes to keep (e.g. eng,spa,und). '
        + 'Tracks with any OTHER language code will trigger Output 1. '
        + '"und" = undetermined - safe to keep as it is typically the only track on '
        + 'single-language files with no language tag.',
    },
  ],
  outputs: [
    { number: 1, tooltip: 'File has non-kept audio AND at least one kept track exists - proceed to removal' },
    { number: 2, tooltip: 'All audio already in keep list, no audio streams, or no kept tracks found (safety)' },
  ],
}); };
exports.details = details;

var plugin = function (args) {
  var keepLangsRaw = (args.inputs && args.inputs.languages_to_keep)
    ? args.inputs.languages_to_keep
    : 'eng,spa,und';

  var keepLangs = String(keepLangsRaw)
    .split(',')
    .map(function (l) { return l.trim().toLowerCase(); })
    .filter(function (l) { return l.length > 0; });

  var streams = (args.inputFileObj.ffProbeData && args.inputFileObj.ffProbeData.streams)
    ? args.inputFileObj.ffProbeData.streams
    : [];

  var audioStreams = streams.filter(function (s) { return s.codec_type === 'audio'; });

  if (audioStreams.length === 0) {
    args.jobLog('No audio streams found - routing to Output 2');
    return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
  }

  var keptStreams = audioStreams.filter(function (s) {
    var lang = (s.tags && s.tags.language) ? s.tags.language.toLowerCase() : 'und';
    return keepLangs.includes(lang);
  });

  var nonKeptStreams = audioStreams.filter(function (s) {
    var lang = (s.tags && s.tags.language) ? s.tags.language.toLowerCase() : 'und';
    return !keepLangs.includes(lang);
  });

  // Safety: if no kept tracks found, skip entirely to avoid producing a silent file
  if (keptStreams.length === 0) {
    args.jobLog('WARNING: No audio tracks in keep list found - skipping to avoid silent file. Tracks: '
      + audioStreams.map(function (s) { return (s.tags && s.tags.language) || 'und'; }).join(', '));
    return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
  }

  if (nonKeptStreams.length > 0) {
    args.jobLog('Non-kept audio found: '
      + nonKeptStreams.map(function (s) { return '[' + s.index + '] ' + ((s.tags && s.tags.language) || 'und'); }).join(', ')
      + ' - routing to Output 1');
    return { outputFileObj: args.inputFileObj, outputNumber: 1, variables: args.variables };
  }

  args.jobLog('All audio in keep list - routing to Output 2');
  return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
};
exports.plugin = plugin;
