;(function(root, factory) {
  "use strict";

  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.ReynardChatGPTLightSessionTrimmer = api;
  if (root.window && root.window !== root) {
    root.window.ReynardChatGPTLightSessionTrimmer = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
  "use strict";

  const HIDDEN_ROLES = new Set(["system", "tool", "thinking"]);
  const DEFAULT_KEEP = 20;
  const MIN_KEEP = 1;
  const MAX_KEEP = 100;

  const result = (changed, data, visibleKept, visibleTotal, skipReason, error) => ({
    changed: Boolean(changed),
    data,
    visibleKept: visibleKept || 0,
    visibleTotal: visibleTotal || 0,
    skipReason: skipReason || null,
    error: error || null,
  });

  const isRecord = value =>
    value !== null && typeof value === "object" && !Array.isArray(value);

  const cloneJSON = value => JSON.parse(JSON.stringify(value));

  const sanitizeKeep = keepCount => {
    const numeric = Number(keepCount);
    if (!Number.isFinite(numeric)) {
      return DEFAULT_KEEP;
    }
    return Math.min(MAX_KEEP, Math.max(MIN_KEEP, Math.round(numeric)));
  };

  const messageRole = node => {
    const role = node?.message?.author?.role;
    return typeof role === "string" ? role : "";
  };

  const isVisibleMessage = node => {
    const role = messageRole(node);
    return Boolean(role) && !HIDDEN_ROLES.has(role);
  };

  const countVisibleTurns = (path, mapping) => {
    let total = 0;
    let previousRole = null;
    for (const nodeId of path) {
      const node = mapping[nodeId];
      if (!isVisibleMessage(node)) {
        continue;
      }
      const role = messageRole(node);
      if (role !== previousRole) {
        total += 1;
        previousRole = role;
      }
    }
    return total;
  };

  const activePath = (mapping, currentNode) => {
    const reversed = [];
    const visited = new Set();
    let cursor = currentNode;

    while (cursor) {
      if (visited.has(cursor)) {
        return { error: "cyclic" };
      }
      visited.add(cursor);

      const node = mapping[cursor];
      if (!isRecord(node)) {
        return { error: "malformed" };
      }
      reversed.push(cursor);

      const parent = node.parent ?? null;
      if (parent !== null && typeof parent !== "string") {
        return { error: "malformed" };
      }
      if (parent !== null && !Object.prototype.hasOwnProperty.call(mapping, parent)) {
        return { error: "malformed" };
      }
      cursor = parent;
    }

    return { path: reversed.reverse() };
  };

  const validateLinearPath = (path, mapping) => {
    for (let index = 0; index < path.length; index += 1) {
      const node = mapping[path[index]];
      if (!isRecord(node)) {
        return "malformed";
      }

      const children = node.children ?? [];
      if (!Array.isArray(children)) {
        return "unsupported-shape";
      }

      const knownChildren = children.filter(child =>
        Object.prototype.hasOwnProperty.call(mapping, child)
      );
      if (knownChildren.length > 1) {
        return "branched-unknown";
      }

      const next = path[index + 1];
      if (next && knownChildren.length > 0 && knownChildren[0] !== next) {
        return "malformed";
      }
    }

    return null;
  };

  const trimConversation = (conversationJson, keepCount) => {
    try {
      if (!isRecord(conversationJson)) {
        return result(false, conversationJson, 0, 0, "malformed", null);
      }

      const mapping = conversationJson.mapping;
      if (!isRecord(mapping)) {
        return result(false, conversationJson, 0, 0, "unsupported-shape", null);
      }

      const mappingIds = Object.keys(mapping);
      if (!mappingIds.length) {
        return result(false, conversationJson, 0, 0, "empty", null);
      }

      const currentNode = conversationJson.current_node;
      if (
        typeof currentNode !== "string" ||
        !Object.prototype.hasOwnProperty.call(mapping, currentNode)
      ) {
        return result(false, conversationJson, 0, 0, "malformed", null);
      }

      const pathResult = activePath(mapping, currentNode);
      if (pathResult.error) {
        return result(false, conversationJson, 0, 0, pathResult.error, null);
      }

      const path = pathResult.path || [];
      if (!path.length) {
        return result(false, conversationJson, 0, 0, "empty", null);
      }

      const pathValidationError = validateLinearPath(path, mapping);
      if (pathValidationError) {
        return result(false, conversationJson, 0, 0, pathValidationError, null);
      }

      const visibleTotal = countVisibleTurns(path, mapping);
      if (visibleTotal <= 0) {
        return result(false, conversationJson, 0, visibleTotal, "empty", null);
      }

      const keep = sanitizeKeep(keepCount);
      if (visibleTotal <= keep) {
        return result(false, conversationJson, visibleTotal, visibleTotal, "short", null);
      }

      let visibleSeen = 0;
      let lastRole = null;
      let cutIndex = 0;

      for (let index = path.length - 1; index >= 0; index -= 1) {
        const node = mapping[path[index]];
        if (!isVisibleMessage(node)) {
          continue;
        }

        const role = messageRole(node);
        if (role !== lastRole) {
          visibleSeen += 1;
          lastRole = role;
        }

        if (visibleSeen > keep) {
          cutIndex = index + 1;
          break;
        }
      }

      const keptPath = path.slice(cutIndex);
      if (!keptPath.length) {
        return result(false, conversationJson, 0, visibleTotal, "malformed", null);
      }

      const originalRoot = path[0];
      const originalRootNode = mapping[originalRoot];
      const finalPath =
        !keptPath.includes(originalRoot) && originalRootNode && !isVisibleMessage(originalRootNode)
          ? [originalRoot].concat(keptPath)
          : keptPath;

      const output = cloneJSON(conversationJson);
      const newMapping = {};
      for (let index = 0; index < finalPath.length; index += 1) {
        const nodeId = finalPath[index];
        const previousId = finalPath[index - 1] || null;
        const nextId = finalPath[index + 1] || null;
        const originalNode = mapping[nodeId];
        if (!isRecord(originalNode)) {
          return result(false, conversationJson, 0, visibleTotal, "malformed", null);
        }

        newMapping[nodeId] = Object.assign(cloneJSON(originalNode), {
          parent: previousId,
          children: nextId ? [nextId] : [],
        });
      }

      const visibleKept = countVisibleTurns(finalPath, newMapping);
      if (visibleKept <= 0 || visibleKept >= visibleTotal) {
        return result(false, conversationJson, visibleKept, visibleTotal, "short", null);
      }

      output.mapping = newMapping;
      output.root = finalPath[0];
      output.current_node = finalPath[finalPath.length - 1];

      return result(true, output, visibleKept, visibleTotal, null, null);
    } catch (error) {
      return result(
        false,
        conversationJson,
        0,
        0,
        null,
        error && error.message ? String(error.message) : String(error)
      );
    }
  };

  return {
    trimConversation,
    isVisibleMessage,
    countVisibleTurns,
  };
});
