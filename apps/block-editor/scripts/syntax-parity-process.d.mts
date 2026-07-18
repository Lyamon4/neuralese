export type ProcessResultLike = {
  status?: number | null;
};

export function failureExitCode(result: ProcessResultLike): number;
