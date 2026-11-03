/* global axios */

import { downloadFile } from '@chatwoot/utils';

// Exact dashboard route that serves access-controlled attachment bytes.
// Only same-origin URLs matching this shape go through the authenticated
// session; every other URL keeps the legacy code path untouched.
export const PROTECTED_ATTACHMENT_PATH_PATTERN =
  /^\/api\/v1\/accounts\/\d+\/connecta_attachments\/\d+\/download$/;

const BLOB_URL_PREFIX = 'blob:';
const DATA_URL_PREFIX = 'data:';

// True only for same-origin URLs on the exact protected download route.
// Relative paths resolve against the dashboard origin; blob:/data: URLs,
// cross-origin URLs and arbitrary same-origin paths never qualify, so no
// auth header can leak to an external host or an unrelated route.
export const isProtectedAttachmentUrl = url => {
  if (!url || typeof url !== 'string') return false;
  if (url.startsWith(BLOB_URL_PREFIX) || url.startsWith(DATA_URL_PREFIX)) {
    return false;
  }

  let parsed = null;
  try {
    parsed = new URL(url, window.location.origin);
  } catch {
    return false;
  }

  if (parsed.origin !== window.location.origin) return false;
  return PROTECTED_ATTACHMENT_PATH_PATTERN.test(parsed.pathname);
};

export const extractFileNameFromContentDisposition = header => {
  if (!header || typeof header !== 'string') return '';
  const match = header.match(
    /filename\*=UTF-8''([^;]+)|filename="([^"]+)"|filename=([^;]+)/i
  );
  if (!match) return '';
  const raw = (match[1] || match[2] || match[3] || '').trim();
  if (!raw) return '';
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
};

// Display-oriented filename taken from a URL. Protected download URLs end
// in a literal `/download` segment, so they carry no usable name: callers
// must prefer the Content-Disposition filename from the authenticated
// fetch and fall back to an explicit placeholder instead.
export const fileNameFromUrl = url => {
  if (!url || typeof url !== 'string') return '';
  if (isProtectedAttachmentUrl(url)) return '';
  const lastSegment = url.split('/').pop().split(/[?#]/)[0] || '';
  try {
    return decodeURIComponent(lastSegment);
  } catch {
    return lastSegment;
  }
};

// Fetches protected attachment bytes through the authenticated dashboard
// session (global axios already carries the auth headers). The query string
// (access token) is preserved; the fragment, if any, is dropped by the
// request itself.
export const fetchProtectedAttachment = async (url, { signal } = {}) => {
  const response = await axios.get(url, { responseType: 'blob', signal });
  const blob =
    response.data instanceof Blob ? response.data : new Blob([response.data]);
  const headers = response.headers || {};
  return {
    blob,
    contentType: headers['content-type'] || blob.type || '',
    fileName: extractFileNameFromContentDisposition(
      headers['content-disposition']
    ),
  };
};

const triggerBlobDownload = (objectUrl, fileName) => {
  const link = document.createElement('a');
  link.href = objectUrl;
  link.download = fileName;
  link.rel = 'noopener';
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
};

export const downloadProtectedAttachment = async ({
  url,
  fileName,
  fileType,
  extension,
}) => {
  const { blob, fileName: headerFileName } =
    await fetchProtectedAttachment(url);
  const name =
    fileName ||
    headerFileName ||
    `attachment-${Date.now()}.${extension || fileType || 'bin'}`;
  triggerBlobDownload(URL.createObjectURL(blob), name);
};

// Single download entry point for dashboard attachments. Protected URLs
// are fetched with the session and saved as a Blob (preserving the
// server-provided filename); every other URL keeps the existing
// fetch-based downloadFile path with no new headers.
export const downloadAttachmentFile = async ({
  url,
  fileType,
  extension,
  fileName,
}) => {
  if (isProtectedAttachmentUrl(url)) {
    await downloadProtectedAttachment({ url, fileName, fileType, extension });
    return;
  }
  await downloadFile({ url, type: fileType, extension });
};

// Appends a cache-busting timestamp only when it is safe: blob:/data:
// URLs (already-resolved protected media) must stay untouched, and the
// helper must never throw on relative URLs.
export const withMediaTimestamp = url => {
  if (!url || typeof url !== 'string') return url;
  if (url.startsWith(BLOB_URL_PREFIX) || url.startsWith(DATA_URL_PREFIX)) {
    return url;
  }
  const hashIndex = url.indexOf('#');
  const base = hashIndex === -1 ? url : url.slice(0, hashIndex);
  const hash = hashIndex === -1 ? '' : url.slice(hashIndex);
  const separator = base.includes('?') ? '&' : '?';
  return `${base}${separator}t=${Date.now()}${hash}`;
};

// Appends a media fragment (e.g. `t=0.1` for video previews) only when it
// is safe: blob:/data: URLs must stay untouched.
export const withMediaFragment = (url, fragment = 't=0.1') => {
  if (!url || typeof url !== 'string') return url;
  if (url.startsWith(BLOB_URL_PREFIX) || url.startsWith(DATA_URL_PREFIX)) {
    return url;
  }
  if (url.includes('#')) return url;
  return `${url}#${fragment}`;
};
