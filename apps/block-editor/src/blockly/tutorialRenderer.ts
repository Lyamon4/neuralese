import * as Blockly from "blockly";
import type { ConnectionShapeSchema } from "../core/schemaTypes";

export const TUTORIAL_RENDERER_NAME = "neuralese_tutorial_v2";

let configuredShapes = new Map<string, ConnectionShapeSchema>();

export function createConnectionNotch(
  shape: ConnectionShapeSchema,
  type: number,
): Blockly.blockRendering.Notch {
  return {
    type,
    width: shape.width,
    height: shape.height,
    pathLeft: shape.pathLeft,
    pathRight: shape.pathRight,
  };
}

export function resolveConnectionNotch(
  checks: string[] | null,
  shapes: ReadonlyMap<string, ConnectionShapeSchema>,
  fallback: Blockly.blockRendering.Notch,
): Blockly.blockRendering.Notch {
  for (const check of checks ?? []) {
    const shape = shapes.get(check);
    if (shape) return createConnectionNotch(shape, fallback.type);
  }
  return fallback;
}

export function configureTutorialRenderer(
  shapes: ReadonlyMap<string, ConnectionShapeSchema>,
): void {
  configuredShapes = new Map(shapes);
  if (Blockly.registry.hasItem(Blockly.registry.Type.RENDERER, TUTORIAL_RENDERER_NAME)) {
    Blockly.registry.unregister(
      Blockly.registry.Type.RENDERER,
      TUTORIAL_RENDERER_NAME,
    );
  }
  Blockly.blockRendering.register(TUTORIAL_RENDERER_NAME, TutorialRenderer);
}

export class TutorialConstantProvider extends Blockly.zelos.ConstantProvider {
  constructor() {
    super();
    this.FIELD_DROPDOWN_COLOURED_DIV = false;
    this.FIELD_DROPDOWN_SVG_ARROW = true;
  }

  override shapeFor(connection: Blockly.RenderedConnection) {
    const fallback = super.shapeFor(connection);
    const isStatement =
      connection.type === Blockly.ConnectionType.PREVIOUS_STATEMENT ||
      connection.type === Blockly.ConnectionType.NEXT_STATEMENT;

    if (!isStatement || !isNotch(fallback)) {
      return fallback;
    }

    return resolveConnectionNotch(connection.getCheck(), configuredShapes, fallback);
  }
}

export class TutorialPathObject extends Blockly.zelos.PathObject {
  override updateSelected(_enable: boolean): void {
  }

  override updateHighlighted(_enable: boolean): void {
  }

  override updateReplacementFade(_enable: boolean): void {
  }

  override updateShapeForInputHighlight(
    _conn: Blockly.Connection,
    _enable: boolean,
  ): void {
  }

  override addConnectionHighlight(
    connection: Blockly.RenderedConnection,
    connectionPath: string,
    offset: Blockly.utils.Coordinate,
    rtl: boolean,
  ): SVGElement {
    const hiddenPath = super.addConnectionHighlight(
      connection,
      connectionPath,
      offset,
      rtl,
    );
    hiddenPath.setAttribute("class", "blocklyHighlightedConnectionPath");
    hiddenPath.setAttribute("fill", "none");
    hiddenPath.setAttribute("stroke", "none");
    hiddenPath.style.setProperty("display", "none", "important");
    hiddenPath.style.setProperty("fill", "none", "important");
    hiddenPath.style.setProperty("stroke", "none", "important");
    hiddenPath.style.setProperty("fill-opacity", "0", "important");
    hiddenPath.style.setProperty("stroke-opacity", "0", "important");
    return hiddenPath;
  }
}

function isNotch(
  shape: ReturnType<Blockly.zelos.ConstantProvider["shapeFor"]>,
): shape is Blockly.blockRendering.Notch {
  return "pathLeft" in shape && "pathRight" in shape;
}

class TutorialRenderer extends Blockly.zelos.Renderer {
  protected override makeConstants_(): Blockly.zelos.ConstantProvider {
    return new TutorialConstantProvider();
  }

  override makePathObject(
    root: SVGElement,
    style: Blockly.Theme.BlockStyle,
  ): TutorialPathObject {
    return new TutorialPathObject(root, style, this.getConstants());
  }
}
