"use strict";
// Tdarr Local Flow Plugin: Discord Notify
// Version: 1.0.0
//
// PURPOSE:
//   Sends a colored Discord embed notification via webhook. Severity
//   controls the embed sidebar color for easy visual triage in Discord.
//   HTML entities in file paths (e.g. &#x2F; -> /) are automatically
//   decoded so messages are clean and readable.
//
// SEVERITY COLORS:
//   success → green  (#2ECC71) — tracks removed successfully
//   warning → yellow (#FFFF00) — missing expected languages, needs review
//   error   → red    (#E74C3C) — FFmpeg failure or processing error
//   info    → blue   (#3498DB) — general informational message
//
// INSTALL:
//   Copy to:
//   /mnt/user/appdata/tdarr/server/Tdarr/Plugins/FlowPlugins/LocalFlowPlugins/notification/discordNotify/1.0.0/index.js
//   Then click "Sync node plugins" in Tdarr Flows page.
//
// USAGE IN FLOW:
//   Place after Replace Original File (success), after missing-language
//   branch (warning), or on error branches (error). Connect both Output 1
//   and Output 2 to next node so flow always continues regardless of
//   notification success/failure.
//
// NOTE:
//   Webhook URL should be passed as a plugin input, not hardcoded.
//   Use the full https://discord.com/api/webhooks/ID/TOKEN format.

Object.defineProperty(exports, "__esModule", { value: true });
exports.plugin = exports.details = void 0;

var details = function () { return ({
  name: 'Discord Notify',
  description: 'Sends a colored Discord embed notification via webhook. '
    + 'Severity controls embed color: success=green, warning=yellow, error=red, info=blue. '
    + 'HTML entities in file paths are automatically decoded.',
  style: { borderColor: 'blue' },
  tags: 'notification,discord',
  isStartPlugin: false,
  pType: '',
  requiresVersion: '2.11.01',
  sidebarPosition: -1,
  icon: 'faBell',
  inputs: [
    {
      label: 'Webhook URL',
      name: 'webhook_url',
      type: 'string',
      defaultValue: 'https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN',
      inputUI: { type: 'text' },
      tooltip: 'Full Discord webhook URL (https://discord.com/api/webhooks/...)',
    },
    {
      label: 'Title',
      name: 'title',
      type: 'string',
      defaultValue: 'Tdarr Notification',
      inputUI: { type: 'text' },
      tooltip: 'Embed title shown in bold at the top of the Discord message.',
    },
    {
      label: 'Message',
      name: 'message',
      type: 'string',
      defaultValue: '{{args.inputFileObj.fileNameWithoutExtension}}',
      inputUI: { type: 'text' },
      tooltip: 'Message body. Supports Tdarr variables e.g. '
        + '{{args.inputFileObj.fileNameWithoutExtension}} or '
        + '{{args.inputFileObj.meta.Directory}}',
    },
    {
      label: 'Severity',
      name: 'severity',
      type: 'string',
      defaultValue: 'success',
      inputUI: {
        type: 'dropdown',
        options: ['success', 'warning', 'error', 'info'],
      },
      tooltip: 'Controls the embed sidebar color. success=green, warning=yellow, error=red, info=blue.',
    },
  ],
  outputs: [
    { number: 1, tooltip: 'Notification sent successfully (HTTP 204)' },
    { number: 2, tooltip: 'Notification failed - flow continues regardless' },
  ],
}); };
exports.details = details;

var plugin = function (args) {
  var exec = require('child_process').execSync;

  // Load inputs with fallbacks
  var webhookUrl = (args.inputs && args.inputs.webhook_url) ? String(args.inputs.webhook_url) : '';
  var title      = (args.inputs && args.inputs.title)       ? String(args.inputs.title)       : 'Tdarr Notification';
  var message    = (args.inputs && args.inputs.message)     ? String(args.inputs.message)     : '';
  var severity   = (args.inputs && args.inputs.severity)    ? String(args.inputs.severity)    : 'success';

  // Decode common HTML entities that appear when Apprise or other tools
  // encode path separators and special characters for Discord
  function decodeHtml(str) {
    return str
      .replace(/&#x2F;/g,  '/')
      .replace(/&#x3A;/g,  ':')
      .replace(/&#x3D;/g,  '=')
      .replace(/&#x3F;/g,  '?')
      .replace(/&#x26;/g,  '&')
      .replace(/&#x22;/g,  '"')
      .replace(/&#x27;/g,  "'")
      .replace(/&#x60;/g,  '`')
      .replace(/&amp;/g,   '&')
      .replace(/&lt;/g,    '<')
      .replace(/&gt;/g,    '>')
      .replace(/&quot;/g,  '"')
      .replace(/&#39;/g,   "'");
  }

  title   = decodeHtml(title);
  message = decodeHtml(message);

  // Map severity to Discord embed color (decimal RGB)
  var colorMap = {
    success: 3066993,   // green  #2ECC71
    warning: 16776960,  // yellow #FFFF00
    error:   15158332,  // red    #E74C3C
    info:    3447003,   // blue   #3498DB
  };
  var color = colorMap[severity] || colorMap.info;

  // Prefix titles with severity indicator for quick visual scanning
  var emojiMap = {
    success: '[+]',
    warning: '[!]',
    error:   '[x]',
    info:    '[i]',
  };
  var prefix = emojiMap[severity] || '[i]';

  if (!webhookUrl || webhookUrl.indexOf('discord.com') === -1) {
    args.jobLog('Discord Notify: Invalid or missing webhook URL - skipping');
    return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
  }

  // Build Discord embed payload
  var payload = JSON.stringify({
    embeds: [{
      title:       prefix + ' ' + title,
      description: message,
      color:       color,
      footer:      { text: 'Caladan / Tdarr' },
    }]
  });

  // Single-quote escape for shell safety
  var escapedPayload = payload.replace(/'/g, "'\\''");

  try {
    var result = exec(
      "curl -s -o /tmp/discord_notify_response.json -w '%{http_code}' " +
      "-X POST -H 'Content-Type: application/json' " +
      "-d '" + escapedPayload + "' " +
      "'" + webhookUrl + "'",
      { timeout: 10000 }
    );
    var httpCode = String(result).trim();
    if (httpCode === '204') {
      args.jobLog('Discord Notify: Sent successfully (HTTP 204)');
      return { outputFileObj: args.inputFileObj, outputNumber: 1, variables: args.variables };
    } else {
      args.jobLog('Discord Notify: Unexpected HTTP ' + httpCode + ' - check webhook URL');
      return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
    }
  } catch (err) {
    args.jobLog('Discord Notify: curl failed - ' + String(err.message || err));
    return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
  }
};
exports.plugin = plugin;
