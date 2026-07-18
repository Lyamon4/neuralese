export type AstBlock = {
  type: string;
  fields: Record<string, unknown>;
  children: AstBlock[];
  inputs: Record<string, AstBlock[]>;
};

export type LessonAst = {
  bundleName: string;
  lessons: Array<{
    key: string;
    title: string;
    blocks: AstBlock[];
  }>;
};
