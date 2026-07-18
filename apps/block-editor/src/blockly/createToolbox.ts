import type { LoadedTutorialSchema } from "../core/schemaTypes";

export function createToolbox(loaded: LoadedTutorialSchema) {
  return {
    kind: "categoryToolbox",
    contents: [
      ...loaded.toolboxCategories
        .map((category) => {
          const visibleBlockTypes = category.blockTypes.filter(
            (type) => loaded.blocksByType.get(type)?.toolboxVisible !== false,
          );
          const categoryColour = loaded.blocksByType.get(
            visibleBlockTypes[0],
          )?.colour;

          return {
            kind: "category",
            name: category.name,
            colour: categoryColour,
            contents: visibleBlockTypes.map((type) => ({
              kind: "block",
              type,
            })),
          };
        })
        .filter((category) => category.contents.length > 0),
    ],
  };
}
