export function failureExitCode(result) {
  const status = result?.status;
  return Number.isInteger(status) && status !== 0 ? status : 2;
}
