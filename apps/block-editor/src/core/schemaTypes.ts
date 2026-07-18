export type FieldType =
  | "text"
  | "textarea"
  | "label"
  | "slug"
  | "bool"
  | "number"
  | "select"
  | "string_list"
  | "option_list"
  | "node_type"
  | "node_alias"
  | "event_name"
  | "wait_mode"
  | "branch_ref"
  | "config_expr"
  | "edge_list";

export type ConnectionCheck =
  | "lesson_step"
  | "action"
  | "requirement"
  | "branch"
  | "topology_node"
  | "topology_edge"
  | "quiz_option"
  | "create_binding"
  | "highlight_target";

export type ConnectionShapeSchema = {
  width: number;
  height: number;
  pathLeft: string;
  pathRight: string;
};

export type SelectOption = {
  label: string;
  value: string;
};

export type TutorialFieldSchema = {
  name: string;
  type: FieldType;
  label: string;
  default?: unknown;
  options?: SelectOption[];
  min?: number;
  max?: number;
  precision?: number;
  teacherVisible?: boolean;
  required?: boolean;
  symbol?: {
    namespace: string;
    role: "definition" | "reference";
  };
  visibleWhen?: {
    field: string;
    equals?: unknown;
    notEmpty?: boolean;
  };
};

export type StatementInputSchema = {
  name: string;
  label: string;
  check: ConnectionCheck | ConnectionCheck[];
  required?: boolean;
};

export type EmitRule =
  | { op: "literal"; value: unknown }
  | {
      op: "field";
      name: string;
      default?: unknown;
      coerce?: "number" | "boolean" | "lines" | "integerList";
    }
  | { op: "template"; value: string }
  | { op: "object"; fields: Record<string, EmitRule>; omitEmpty?: boolean }
  | { op: "array"; items: EmitRule[] }
  | { op: "singleKeyMapping"; key: EmitRule; value: EmitRule }
  | { op: "children"; input?: string }
  | { op: "childrenObject"; input: string }
  | {
      op: "when";
      field: string;
      equals?: unknown;
      notEmpty?: boolean;
      then: EmitRule;
      otherwise?: EmitRule;
    }
  | { op: "computedKey"; template: string; value: EmitRule };

export type TutorialBlockSchema = {
  type: string;
  message: string;
  category: string;
  colour: number | string;
  kind: "statement" | "hat" | "value";
  tooltip?: string;
  fields: TutorialFieldSchema[];
  role?: "lesson_root" | "lesson_branch";
  branchNameField?: string;
  toolboxVisible?: boolean;
  stackInput?: string;
  dsl?:
    | {
        kind: "action" | "requirement";
        key: string;
      }
    | Array<{
        kind: "action" | "requirement";
        key: string;
      }>;
  connection?: {
    previous?: ConnectionCheck | null;
    next?: ConnectionCheck | null;
    output?: ConnectionCheck | null;
  };
  statementInputs?: StatementInputSchema[];
  emit: EmitRule;
};

export type TutorialSchema = {
  schemaVersion: number;
  connectionShapes: Record<string, ConnectionShapeSchema>;
  blocks: TutorialBlockSchema[];
};

export type TutorialNodeCatalog = {
  schemaVersion: number;
  nodes: Array<{
    id: string;
    label: string;
    runtimeLabel?: string;
  }>;
};

export type LoadedTutorialSchema = {
  blocksByType: Map<string, TutorialBlockSchema>;
  emitRulesByType: Map<string, EmitRule>;
  connectionShapes: Map<string, ConnectionShapeSchema>;
  toolboxCategories: Array<{ name: string; blockTypes: string[] }>;
};
