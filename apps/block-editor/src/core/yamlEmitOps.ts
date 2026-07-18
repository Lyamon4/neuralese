export type SerializableBlock = {
  type: string;
  fields: Record<string, unknown>;
  children: SerializableBlock[];
  inputs?: Record<string, SerializableBlock[]>;
};

export type EmitContext = {
  block: SerializableBlock;
  emitRulesByType: Map<string, unknown>;
};
