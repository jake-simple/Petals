/* Petals App Store compositor: drops a real captured app window into a
   marketing poster (background + headline + optional decorations / panel). */
(function () {
  "use strict";

  var PALETTE = ["#FF3B30", "#FF9500", "#FFB300", "#34C759", "#00C2A8",
                 "#30B0C7", "#007AFF", "#5856D6", "#AF52DE", "#FF2D70"];

  // theme swatch preview colors (mirrors Petals/Theme/Themes.json)
  var THEMES = {
    "minimal-light": { bg: "#FFFFFF", grid: "#E0E0E0", today: "#FF6B35" },
    "pastel":        { bg: "#FFF5F5", grid: "#E8D5D5", today: "#FF8FA3" },
    "classic":       { bg: "#F5F0E8", grid: "#C8B8A0", today: "#8B4513" },
    "nord":          { bg: "#ECEFF4", grid: "#D8DEE9", today: "#5E81AC" },
    "tokyo-night":   { bg: "#1A1B26", grid: "#292E42", today: "#7AA2F7" },
    "dracula":       { bg: "#282A36", grid: "#44475A", today: "#FF79C6" },
    "midnight":      { bg: "#1A1A2E", grid: "#2A2A4A", today: "#00D4FF" },
    "monochrome":    { bg: "#FFFFFF", grid: "#000000", today: "#000000" },
    "solarized":     { bg: "#FDF6E3", grid: "#EEE8D5", today: "#CB4B16" }
  };

  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      var t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  function elm(cls, html) {
    var d = document.createElement("div");
    if (cls) d.className = cls;
    if (html != null) d.innerHTML = html;
    return d;
  }

  function buildSwatchPanel(active) {
    var panel = elm("panel");
    var row = elm("swatch-row");
    var order = [
      ["minimal-light", "Minimal"], ["pastel", "Pastel"], ["classic", "Classic"],
      ["nord", "Nord"], ["tokyo-night", "Tokyo Night"], ["dracula", "Dracula"],
      ["midnight", "Midnight"], ["monochrome", "Monochrome"], ["solarized", "Solarized"]
    ];
    order.forEach(function (o) {
      var t = THEMES[o[0]];
      var sw = elm("swatch" + (o[0] === active ? " on" : ""));
      var prev = elm("sw-prev");
      prev.style.background = t.bg;
      prev.style.boxShadow = "inset 0 0 0 1px " + t.grid;
      var rnd = mulberry32(o[0].length * 97 + 13);
      for (var i = 0; i < 3; i++) {
        var bar = elm("bar");
        bar.style.background = PALETTE[Math.floor(rnd() * PALETTE.length)];
        bar.style.top = (10 + i * 13) + "px";
        bar.style.left = (8 + rnd() * 15) + "px";
        bar.style.width = (36 + rnd() * 46) + "px";
        prev.appendChild(bar);
      }
      var tline = document.createElement("div");
      tline.style.cssText = "position:absolute;top:6px;bottom:6px;width:2px;left:63%;background:" + t.today;
      prev.appendChild(tline);
      sw.appendChild(prev);
      sw.appendChild(elm("sw-name", o[1]));
      row.appendChild(sw);
    });
    panel.appendChild(row);
    return panel;
  }

  function buildFeaturePanel(features) {
    var panel = elm("panel");
    var row = elm("feature-row");
    features.forEach(function (f) {
      var card = elm("feature");
      var ic = elm("fi", f.icon);
      ic.style.background = f.tint;
      card.appendChild(ic);
      var txt = document.createElement("div");
      txt.appendChild(elm("ft", f.title));
      txt.appendChild(elm("fd", f.desc));
      card.appendChild(txt);
      row.appendChild(card);
    });
    panel.appendChild(row);
    return panel;
  }

  function render() {
    var S = window.SCENE;
    var poster = elm("poster");
    poster.style.background = S.poster.bg;

    if (S.poster.glow) {
      var g1 = elm("poster-glow");
      g1.style.background = S.poster.glow[0];
      g1.style.left = "-170px"; g1.style.top = "-250px";
      poster.appendChild(g1);
      var g2 = elm("poster-glow");
      g2.style.background = S.poster.glow[1];
      g2.style.right = "-190px"; g2.style.bottom = "-280px";
      poster.appendChild(g2);
    }

    var hb = elm("headline-block");
    var h = elm("headline", S.poster.headline);
    h.style.color = S.poster.ink || "#1c1c1e";
    hb.appendChild(h);
    var sub = elm("subhead", S.poster.sub);
    sub.style.color = S.poster.ink || "#1c1c1e";
    hb.appendChild(sub);
    poster.appendChild(hb);

    var stage = elm("stage");
    var img = document.createElement("img");
    img.className = "shot";
    img.src = S.shot;
    img.style.width = (S.shotWidth || 1140) + "px";
    stage.appendChild(img);

    if (S.decorations) {
      S.decorations.forEach(function (d) {
        var node = elm("deco " + (d.text ? "txt" : "emoji"));
        node.textContent = d.text || d.emoji;
        node.style.left = d.x + "%";
        node.style.top = d.y + "%";
        var tr = "translate(-50%,-50%)";
        if (d.rot) tr += " rotate(" + d.rot + "deg)";
        node.style.transform = tr;
        node.style.fontSize = (d.size || (d.text ? 26 : 40)) + "px";
        if (d.text) {
          node.style.color = d.color || "#FF2D70";
          if (d.font) node.style.fontFamily = d.font;
        }
        stage.appendChild(node);
      });
    }
    poster.appendChild(stage);

    if (S.panel) {
      if (S.panel.type === "themes") {
        poster.appendChild(buildSwatchPanel(S.panel.active));
      } else if (S.panel.type === "features") {
        poster.appendChild(buildFeaturePanel(S.panel.features));
      }
    }

    document.body.appendChild(poster);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", render);
  } else {
    render();
  }
})();
