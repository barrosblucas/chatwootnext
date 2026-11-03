import { ref, watch, onBeforeUnmount } from 'vue';
import {
  isProtectedAttachmentUrl,
  fetchProtectedAttachment,
} from 'dashboard/helper/connectaProtectedMedia';

const isAbortError = error =>
  error?.code === 'ERR_CANCELED' ||
  error?.name === 'CanceledError' ||
  error?.name === 'AbortError';

// Resolves a dashboard attachment URL into something an <img>/<audio>/
// <video> tag or link can use. Non-protected URLs pass through untouched
// (zero behavior change); protected same-origin download URLs are fetched
// with the authenticated session and exposed as an ObjectURL.
//
// Lifecycle: in-flight fetches are aborted when the source changes or the
// consumer unmounts, stale responses are ignored (no global cache between
// sessions), and the previous ObjectURL is revoked before a new one is
// published. `fileName` carries the Content-Disposition filename when the
// server provides one.
export const useProtectedAttachmentUrl = source => {
  const resolvedUrl = ref(null);
  const isResolving = ref(false);
  const resolveError = ref(null);
  const errorStatus = ref(null);
  const fileName = ref('');

  let objectUrl = null;
  let requestId = 0;
  let abortController = null;

  const getRawUrl = () =>
    typeof source === 'function' ? source() : source?.value;

  const revokeObjectUrl = () => {
    if (!objectUrl) return;
    if (resolvedUrl.value === objectUrl) resolvedUrl.value = null;
    try {
      URL.revokeObjectURL(objectUrl);
    } catch {
      // Revocation is best-effort; a missing entry must not break teardown.
    }
    objectUrl = null;
  };

  const cancelInFlight = () => {
    if (!abortController) return;
    try {
      abortController.abort();
    } catch {
      // Aborting is best-effort; teardown continues regardless.
    }
    abortController = null;
  };

  const resolve = async () => {
    const rawUrl = getRawUrl();
    requestId += 1;
    const currentRequest = requestId;
    cancelInFlight();
    revokeObjectUrl();
    resolveError.value = null;
    errorStatus.value = null;
    fileName.value = '';

    if (!rawUrl) {
      resolvedUrl.value = null;
      isResolving.value = false;
      return;
    }

    if (!isProtectedAttachmentUrl(rawUrl)) {
      resolvedUrl.value = rawUrl;
      isResolving.value = false;
      return;
    }

    isResolving.value = true;
    abortController = new AbortController();
    try {
      const { blob, fileName: headerFileName } = await fetchProtectedAttachment(
        rawUrl,
        {
          signal: abortController.signal,
        }
      );
      if (currentRequest !== requestId) return;
      objectUrl = URL.createObjectURL(blob);
      resolvedUrl.value = objectUrl;
      fileName.value = headerFileName || '';
    } catch (error) {
      if (currentRequest !== requestId) return;
      if (isAbortError(error)) return;
      resolveError.value = error;
      errorStatus.value = error?.response?.status ?? error?.status ?? null;
    } finally {
      if (currentRequest === requestId) {
        isResolving.value = false;
        abortController = null;
      }
    }
  };

  const retry = () => resolve();

  const stopWatching = watch(getRawUrl, () => resolve(), { immediate: true });

  onBeforeUnmount(() => {
    requestId += 1;
    stopWatching();
    cancelInFlight();
    revokeObjectUrl();
  });

  return {
    resolvedUrl,
    isResolving,
    resolveError,
    errorStatus,
    fileName,
    retry,
    resolve,
  };
};
