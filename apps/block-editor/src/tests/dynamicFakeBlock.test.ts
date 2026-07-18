import { describe, expect, it } from "vitest";
import { loadTutorialSchema } from "../core/schemaLoader";
import { emitWorkspaceBlocksToYamlData } from "../core/yamlEmitter";

describe("dynamic fake block", () => {
  it("emits a new block added only through schema JSON", () => {
    const fakeSchema = {
      schemaVersion: 1,
      connectionShapes: {
        action: {
          width: 36,
          height: 8,
          pathLeft: " h 36 ",
          pathRight: " h -36 ",
        },
      },
      blocks: [
        {
          type: "fake_schema_only_action",
          message: "Fake",
          category: "Debug",
          colour: 10,
          kind: "statement",
          fields: [],
          connection: { previous: "action", next: "action" },
          emit: {
            op: "singleKeyMapping",
            key: { op: "literal", value: "fake_action" },
            value: {
              op: "object",
              fields: {
                text: { op: "literal", value: "generated from schema" },
              },
            },
          },
        },
      ],
    };

    const loaded = loadTutorialSchema(fakeSchema);
    const data = emitWorkspaceBlocksToYamlData(
      [{ type: "fake_schema_only_action", fields: {}, children: [], inputs: {} }],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([{ fake_action: { text: "generated from schema" } }]);
  });
});
