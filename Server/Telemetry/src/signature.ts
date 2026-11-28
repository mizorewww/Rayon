import type { Diagnostic, Frame } from "./schema";

/** The first app frame, depth first: where the attributed thread was in Rayon's own code. */
function appFrame(frames: Frame[]): Frame | undefined {
  for (const frame of frames) {
    if (frame.origin === "app" && frame.binaryUUID && frame.offset !== undefined) return frame;
    const inner = appFrame(frame.subFrames);
    if (inner) return inner;
  }
  return undefined;
}

/**
 * Groups items alike, e.g. "crash NSRangeException EXC 1 SIG 11 70B89F27+0x285b8".
 * The frame is a build's binary and code offset, the same on every device.
 * Keep the scalar part in step with migrations/0002_crash_signature.sql.
 */
export function signature(d: Diagnostic): string {
  const stack = d.callStacks.find((s) => s.threadAttributed) ?? d.callStacks[0];
  const frame = stack && appFrame(stack.frames);
  return [
    d.kind,
    d.objcExceptionName,
    d.exceptionType === undefined ? undefined : `EXC ${d.exceptionType}`,
    d.signal === undefined ? undefined : `SIG ${d.signal}`,
    d.terminationReason === "signal" ? undefined : d.terminationReason,
    frame && `${frame.binaryUUID!.slice(0, 8).toUpperCase()}+0x${frame.offset!.toString(16)}`,
  ]
    .filter((part) => part !== undefined)
    .join(" ");
}
