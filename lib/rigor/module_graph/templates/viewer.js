// Cytoscape viewer init. Reads the {nodes, edges, options}
// payload that Viewer::Html emitted into the inline JSON tag,
// then wires filter / search / click handlers.
//
// Kept short on purpose: total review surface for the
// interactivity layer is this file plus the vendored
// cytoscape.min.js (sha256-pinned). See docs/plan.md for the
// supply-chain rationale.
(function () {
  "use strict";

  const data = JSON.parse(document.getElementById("rmg-data").textContent);
  const options = data.options || {};

  // Cytoscape ships several layouts in-core. The picks below
  // are the ones useful for a class/module dependency graph
  // without pulling in a third-party plugin:
  //
  // - cose          force-directed; the only built-in that
  //                 honours compound (namespace) bounds well
  // - breadthfirst  hierarchical BFS tree; good for
  //                 inheritance-heavy graphs
  // - concentric    rings by node degree; surfaces hubs
  // - circle        all nodes on one circle — debug-ish
  // - grid          regular grid — also debug-ish
  //
  // Picking anything other than `cose` will flatten the
  // namespace compound visualisation, since the others don't
  // co-layout parents and children.
  function layoutConfig(name) {
    const common = { animate: false, fit: true, padding: 20 };
    switch (name) {
      case "breadthfirst":
        return Object.assign({}, common, {
          name: "breadthfirst",
          directed: true,
          spacingFactor: 1.4,
          nodeDimensionsIncludeLabels: true
        });
      case "concentric":
        return Object.assign({}, common, {
          name: "concentric",
          minNodeSpacing: 40,
          nodeDimensionsIncludeLabels: true,
          concentric: function (node) { return node.degree(); },
          levelWidth: function () { return 1; }
        });
      case "circle":
        return Object.assign({}, common, {
          name: "circle",
          spacingFactor: 1.2,
          nodeDimensionsIncludeLabels: true
        });
      case "grid":
        return Object.assign({}, common, {
          name: "grid",
          nodeDimensionsIncludeLabels: true
        });
      case "cose":
      default:
        return Object.assign({}, common, {
          name: "cose",
          // Make labels part of the packing so compound
          // parents size to fit their children's labels too.
          nodeDimensionsIncludeLabels: true,
          // Defaults pack very tight in dense graphs; loosen
          // so edge labels stay legible and compounds breathe.
          idealEdgeLength: 90,
          nodeRepulsion: 6000,
          // `nestingFactor` < 1 pulls children toward their
          // parent centre, which keeps namespace compounds
          // from sprawling.
          nestingFactor: 0.8,
          gravity: 0.6
        });
    }
  }

  const cy = cytoscape({
    container: document.getElementById("cy"),
    elements: { nodes: data.nodes, edges: data.edges },
    style: [
      { selector: "node",
        style: {
          "label": "data(name)",
          "font-size": "10px",
          "background-color": "#f8fafc",
          "border-color": "#94a3b8",
          "border-width": 1,
          "shape": "round-rectangle",
          "padding": "4px",
          "text-valign": "center",
          "text-halign": "center"
        }
      },
      { selector: 'node[kind = "external"]',
        style: { "background-color": "#e2e8f0", "color": "#64748b" }
      },
      // Compound parent nodes — namespaces from `--collapse`
      // (or the auto-collapse heuristic). Translucent background
      // so child nodes are still legible, label sits in the
      // top-left corner to mimic the Mermaid `subgraph` look.
      { selector: ":parent",
        style: {
          "background-color": "#f1f5f9",
          "background-opacity": 0.6,
          "border-color": "#cbd5e1",
          "border-width": 1,
          "label": "data(name)",
          "text-valign": "top",
          "text-halign": "left",
          "text-margin-x": 8,
          "text-margin-y": 4,
          "font-size": "12px",
          "font-weight": "bold",
          "color": "#475569",
          "padding": "16px"
        }
      },
      // Compound nodes shouldn't react to the kind/confidence
      // edge filter the way nodes-with-edges do — they "stay
      // visible because they hold the visible children".
      { selector: 'node[kind = "compound"].filtered-out',
        style: { "display": "element" }
      },
      { selector: "edge",
        style: {
          "width": 1,
          "line-color": "#94a3b8",
          "target-arrow-color": "#94a3b8",
          "target-arrow-shape": "triangle",
          "curve-style": "bezier",
          "label": "data(kind)",
          "font-size": "8px",
          "color": "#64748b",
          "text-rotation": "autorotate",
          "text-background-color": "#fff",
          "text-background-padding": "2px",
          "text-background-opacity": 0.9
        }
      },
      { selector: 'edge[kind = "inherits"]',
        style: { "line-color": "#0f172a", "target-arrow-color": "#0f172a", "width": 2 }
      },
      { selector: 'edge[kind = "include"]',
        style: { "line-color": "#1d4ed8", "target-arrow-color": "#1d4ed8" }
      },
      { selector: 'edge[kind = "prepend"]',
        style: { "line-color": "#9333ea", "target-arrow-color": "#9333ea" }
      },
      { selector: 'edge[kind = "extend"]',
        style: { "line-color": "#0f766e", "target-arrow-color": "#0f766e", "line-style": "dashed" }
      },
      { selector: 'edge[kind = "const_ref"]',
        style: { "line-color": "#94a3b8", "target-arrow-color": "#94a3b8", "line-style": "dotted" }
      },
      { selector: 'edge[kind = "association"]',
        style: { "line-color": "#0891b2", "target-arrow-color": "#0891b2" }
      },
      { selector: ".filtered-out", style: { "display": "none" } },
      { selector: ".search-dim", style: { "opacity": 0.15 } }
    ],
    layout: layoutConfig("cose")
  });

  // Distinct kind / confidence values present in this dataset
  // drive the checkbox fieldsets — never hard-coded.
  function uniqValues(attr) {
    return Array.from(new Set(data.edges.map(e => e.data[attr]))).sort();
  }

  function buildCheckboxes(fieldsetId, values) {
    const fs = document.getElementById(fieldsetId);
    values.forEach(v => {
      const label = document.createElement("label");
      const input = document.createElement("input");
      input.type = "checkbox";
      input.value = v;
      input.checked = true;
      input.addEventListener("change", applyFilters);
      label.appendChild(input);
      label.appendChild(document.createTextNode(" " + v));
      fs.appendChild(label);
    });
  }

  function selectedValues(fieldsetId) {
    return new Set(
      Array.from(document.querySelectorAll("#" + fieldsetId + " input:checked"))
        .map(i => i.value)
    );
  }

  function applyFilters() {
    const okKinds = selectedValues("filter-kind");
    const okConfs = selectedValues("filter-confidence");
    cy.batch(() => {
      cy.edges().forEach(e => {
        const ok = okKinds.has(e.data("kind")) && okConfs.has(e.data("confidence"));
        e.toggleClass("filtered-out", !ok);
      });
      // Plain nodes — hide when no visible incident edges so
      // orphans don't clutter the canvas under a tight filter.
      cy.nodes(":childless").forEach(n => {
        if (n.data("kind") === "compound") return;
        const visibleEdges = n.connectedEdges(":not(.filtered-out)");
        n.toggleClass("filtered-out", visibleEdges.length === 0);
      });
      // Compound parents — hide when every child is hidden so
      // the namespace frame doesn't linger as an empty box.
      cy.nodes(":parent").forEach(p => {
        const visibleChildren = p.children(":not(.filtered-out)");
        p.toggleClass("filtered-out", visibleChildren.length === 0);
      });
    });
    updateCounts();
  }

  function applySearch() {
    const q = document.getElementById("search").value.trim().toLowerCase();
    cy.batch(() => {
      if (q === "") {
        cy.elements().removeClass("search-dim");
        return;
      }
      cy.nodes().forEach(n => {
        n.toggleClass("search-dim", !n.data("name").toLowerCase().includes(q));
      });
      cy.edges().forEach(e => {
        const src = e.source().data("name").toLowerCase();
        const tgt = e.target().data("name").toLowerCase();
        e.toggleClass("search-dim", !(src.includes(q) || tgt.includes(q)));
      });
    });
  }

  function updateCounts() {
    const nVisible = cy.nodes(":visible").length;
    const eVisible = cy.edges(":visible").length;
    document.getElementById("counts").textContent =
      nVisible + " nodes, " + eVisible + " edges";
  }

  function handleNodeTap(evt) {
    const n = evt.target;
    const path = n.data("path");
    if (!path) return;
    const line = n.data("line");
    const ref = line ? path + ":" + line : path;
    if (options.open_with === "vscode") {
      window.location.href = "vscode://file/" + ref;
    } else if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(ref).catch(() => {});
    }
  }

  buildCheckboxes("filter-kind", uniqValues("kind"));
  buildCheckboxes("filter-confidence", uniqValues("confidence"));
  document.getElementById("search").addEventListener("input", applySearch);
  document.getElementById("fit").addEventListener("click", () => cy.fit());
  document.getElementById("layout-pick").addEventListener("change", function (e) {
    cy.layout(layoutConfig(e.target.value)).run();
  });
  cy.on("tap", "node", handleNodeTap);
  updateCounts();
})();
