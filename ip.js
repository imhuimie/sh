/**
 * ================================================================
 * Nezha Network Visitor Panel
 * Green-White Glass · Foggy Text Edition (UPDATED)
 * ================================================================
 */

window.VisitorInfoAutoHideDelay = 3600;

/* ================= 工具函数 ================= */

async function measureLatency() {
  const url = "https://cloudflare.com/cdn-cgi/trace";
  const times = [];
  for (let i = 0; i < 10; i++) {
    try {
      const t0 = performance.now();
      await fetch(url, { cache: "no-store" });
      times.push(performance.now() - t0);
    } catch {}
  }
  return times.length
    ? Math.round(times.reduce((a, b) => a + b, 0) / times.length)
    : "N/A";
}

function toEnglishCountryName(code) {
  if (!code) return "N/A";
  try {
    return new Intl.DisplayNames(["en"], { type: "region" }).of(code);
  } catch {
    return code;
  }
}

function safe(v) {
  if (v === null || v === undefined) return "N/A";
  const s = String(v).trim();
  return s.length ? s : "N/A";
}

/* ================= 主入口 ================= */

function initVisitorInfo() {
  fetch("https://ipinfo.io/json")
    .then((res) => res.json())
    .then(async (basic) => {
      let detail = basic;
      try {
        if (basic?.ip) {
          const r = await fetch(`https://ipinfo.io/widget/demo/${basic.ip}`);
          const j = await r.json();
          detail = j.data || basic;
        }
      } catch {}

      const latency = await measureLatency();
      display(detail, latency);
    })
    .catch(() => display({}, "N/A"));

  function display(data, latency) {
    // 清理旧实例
    document.getElementById("nezha-net-glass-panel")?.remove();
    document.getElementById("nezha-net-glass-btn")?.remove();

    /* ================= 强制样式注入（反杀全站白字） ================= */

    if (!document.getElementById("nezha-net-glass-style")) {
      const st = document.createElement("style");
      st.id = "nezha-net-glass-style";
      st.textContent = `
        /* 反杀 .dark * 白字：仅本面板 */
        #nezha-net-glass-panel,
        #nezha-net-glass-panel * {
          color: #1A4D2E !important;
          text-shadow:
            0 1px 0 rgba(255,255,255,0.55),
            0 0 12px rgba(26,77,46,0.22) !important;
        }

        /* 次要文字 */
        #nezha-net-glass-panel .nz-sub {
          color: #5C7065 !important;
          text-shadow:
            0 1px 0 rgba(255,255,255,0.45),
            0 0 10px rgba(26,77,46,0.14) !important;
        }

        /* 数值：略小但更稳 */
        #nezha-net-glass-panel .nz-val {
          color: #2E5945 !important;
          font-weight: 850 !important;
          text-shadow:
            0 1px 0 rgba(255,255,255,0.62),
            0 0 14px rgba(26,77,46,0.24) !important;
        }

        /* 标签：更大更醒目（你要的层级） */
        #nezha-net-glass-panel .nz-lab {
          color: #1A4D2E !important;
          font-weight: 900 !important;
          opacity: 0.98 !important;
        }
      `;
      document.head.appendChild(st);
    }

    /* ================= DOM ================= */

    const panel = document.createElement("div");
    const btn = document.createElement("div");

    panel.id = "nezha-net-glass-panel";
    btn.id = "nezha-net-glass-btn";

    document.body.append(panel, btn);

    /* ================= 国旗 ================= */

    const countryCode = (data.country || "").toLowerCase();
    const flagHTML = countryCode
      ? `<span class="fi fi-${countryCode}" style="display:inline-block;transform:translateY(1px);"></span>`
      : `<span class="fi fi-un" style="display:inline-block;transform:translateY(1px);"></span>`;

    /* ================= 面板样式 ================= */

    Object.assign(panel.style, {
      position: "fixed",
      left: "-380px",
      bottom: "22px",
      width: "360px",
      padding: "16px",
      zIndex: "9999",

      background: "rgba(255,255,255,0.72)",
      backdropFilter: "blur(10px)",
      WebkitBackdropFilter: "blur(10px)",

      border: "1px solid rgba(255,255,255,0.4)",
      borderRadius: "18px",
      boxShadow: "0 8px 32px 0 rgba(31,38,135,0.15)",

      fontFamily:
        '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial',

      transition: "transform .6s cubic-bezier(.22,1,.36,1)",
    });

    /* ================= 折叠按钮（更大更明显但不突兀） =================
       0.8cm -> 1.05cm
       加轻微高光、柔和阴影、hover 提示（不跳）
    =============================================================== */

    Object.assign(btn.style, {
      position: "fixed",
      left: "14px",
      bottom: "22px",
      width: "1.05cm",
      height: "1.05cm",
      borderRadius: "14px",

      display: "flex",
      alignItems: "center",
      justifyContent: "center",

      background: "rgba(255,255,255,0.72)",
      backdropFilter: "blur(10px)",
      WebkitBackdropFilter: "blur(10px)",

      border: "1px solid rgba(255,255,255,0.48)",
      boxShadow:
        "0 10px 26px rgba(31,38,135,0.14), inset 0 1px 0 rgba(255,255,255,0.55)",

      opacity: "0",
      pointerEvents: "none",
      cursor: "pointer",
      transition: "opacity .35s ease, transform .18s ease, box-shadow .18s ease",
      zIndex: "9999",
      userSelect: "none",
    });

    btn.innerHTML = countryCode ? flagHTML : "🌐";

    // hover：轻微“变清晰”提示可点
    btn.onmouseenter = () => {
      btn.style.transform = "translateY(-1px)";
      btn.style.boxShadow =
        "0 12px 30px rgba(31,38,135,0.16), inset 0 1px 0 rgba(255,255,255,0.65)";
    };
    btn.onmouseleave = () => {
      btn.style.transform = "translateY(0)";
      btn.style.boxShadow =
        "0 10px 26px rgba(31,38,135,0.14), inset 0 1px 0 rgba(255,255,255,0.55)";
    };

    /* ================= 内容（标签大于数值） ================= */

    const ip = safe(data.ip);
    const asn = safe(data.asn?.asn || data.asn);
    const org = safe(data.org);
    const countryName = toEnglishCountryName(data.country);

    const row = (label, value, mono = false) => `
      <div style="
        display:flex;
        justify-content:space-between;
        align-items:center;
        margin:8px 0;
        padding:10px 12px;
        border-radius:14px;
        background: rgba(255,255,255,0.32);
        border: 1px solid rgba(255,255,255,0.25);
      ">
        <!-- 标签更大 -->
        <span class="nz-lab" style="font-size:14px;">
          ${label}
        </span>

        <!-- 数值更稳（略小） -->
        <span class="nz-val" style="
          font-size:13px;
          ${mono ? "font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;" : ""}
        ">
          ${value}
        </span>
      </div>
    `;

    panel.innerHTML = `
      <div style="
        display:flex;
        justify-content:space-between;
        align-items:center;
        margin-bottom:10px;
      ">
        <div class="nz-lab" style="font-size:18px;">
          Network
        </div>

        <div style="
          padding:7px 11px;
          border-radius:999px;
          background: rgba(255,255,255,0.35);
          border: 1px solid rgba(255,255,255,0.25);
        ">
          <span class="nz-sub" style="font-size:12px;font-weight:900;">Latency</span>
          <span class="nz-val" style="font-size:12.5px;"> ${safe(latency)} ms</span>
        </div>
      </div>

      ${row("IP", ip, true)}
      ${row("Country", `${flagHTML} ${countryName}`, false)}
      ${row("ASN", asn, true)}

      <div style="
        margin-top:10px;
        padding:12px;
        border-radius:16px;
        background: rgba(255,255,255,0.32);
        border: 1px solid rgba(255,255,255,0.25);
      ">
        <div class="nz-lab" style="font-size:14px;margin-bottom:6px;">
          Organization
        </div>
        <div class="nz-val" style="font-size:13px;line-height:1.35;">
          ${org}
        </div>
      </div>
    `;

    /* ================= 动画 ================= */

    const show = () => {
      panel.style.transform = "translateX(380px)";
    };

    const hide = () => {
      panel.style.transform = "translateX(0)";
      setTimeout(() => {
        btn.style.opacity = "1";
        btn.style.pointerEvents = "auto";
      }, 600);
    };

    setTimeout(show, 260);
    setTimeout(hide, window.VisitorInfoAutoHideDelay + 260);

    btn.onclick = () => {
      btn.style.opacity = "0";
      btn.style.pointerEvents = "none";
      show();
      setTimeout(hide, window.VisitorInfoAutoHideDelay);
    };
  }
}

/* ================= 启动 ================= */

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initVisitorInfo);
} else {
  initVisitorInfo();
}
