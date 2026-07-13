(function () {
  "use strict";

  const button = document.getElementById("platform-download");
  if (!button) return;

  const language = (document.documentElement.lang || "en").toLowerCase();
  const labels = language.startsWith("ja")
    ? {
        macos: "macOS版をダウンロード",
        windows: "Windows版をダウンロード",
        other: "ダウンロード一覧",
      }
    : language.startsWith("zh")
      ? {
          macos: "下载 macOS 版",
          windows: "下载 Windows 版",
          other: "查看下载",
        }
      : {
          macos: "Download for macOS",
          windows: "Download for Windows",
          other: "View downloads",
        };

  const platformText = [
    navigator.userAgentData && navigator.userAgentData.platform,
    navigator.platform,
    navigator.userAgent,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  let platform = "other";
  let assetPattern = null;

  if (/windows|win32|win64/.test(platformText)) {
    platform = "windows";
    assetPattern = /-windows-x64\.zip$/i;
  } else if (/macintosh|macintel|mac os|macos/.test(platformText)) {
    platform = "macos";
    assetPattern = /-macos-universal\.zip$/i;
  }

  button.textContent = labels[platform];
  button.dataset.platform = platform;

  if (!assetPattern) {
    button.removeAttribute("aria-busy");
    return;
  }

  fetch(button.dataset.releaseApi, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then(function (response) {
      if (!response.ok) throw new Error("GitHub release request failed");
      return response.json();
    })
    .then(function (release) {
      const asset = (release.assets || []).find(function (candidate) {
        return assetPattern.test(candidate.name || "");
      });

      if (asset && asset.browser_download_url) {
        button.href = asset.browser_download_url;
        button.dataset.resolved = "true";
      }
    })
    .catch(function () {
      // Keep the GitHub Releases fallback when the API is unavailable.
    })
    .finally(function () {
      button.removeAttribute("aria-busy");
    });
})();
