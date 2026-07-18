import { useEffect, useRef, useState } from "react";

export type NamingDialogKind = "workspace" | "lesson";

type NamingDialogProps = {
  kind: NamingDialogKind;
  open: boolean;
  onCancel: () => void;
  onCreate: (name: string) => void;
};

const dialogCopy = {
  workspace: {
    eyebrow: "New workspace",
    title: "Create workspace",
    description: "Name the workspace. Its first lesson key is generated automatically.",
    label: "Workspace name",
    placeholder: "Image classifier",
  },
  lesson: {
    eyebrow: "New lesson",
    title: "Create lesson",
    description: "Name the lesson. Its export key is generated automatically.",
    label: "Lesson name",
    placeholder: "Model basics",
  },
} as const;

export function NamingDialog({
  kind,
  open,
  onCancel,
  onCreate,
}: NamingDialogProps) {
  const [name, setName] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);
  const copy = dialogCopy[kind];

  useEffect(() => {
    if (!open) return;
    setName("");
    globalThis.setTimeout(() => inputRef.current?.focus(), 0);
  }, [kind, open]);

  if (!open) return null;

  const trimmedName = name.trim();
  const titleId = `${kind}-dialog-title`;

  return (
    <div className="dialogBackdrop" role="presentation" onMouseDown={onCancel}>
      <section
        className="workspaceDialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="dialogHeading">
          <span>{copy.eyebrow}</span>
          <h2 id={titleId}>{copy.title}</h2>
          <p>{copy.description}</p>
        </div>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            if (trimmedName) onCreate(trimmedName);
          }}
        >
          <label className="field dialogField">
            <span>{copy.label}</span>
            <input
              ref={inputRef}
              aria-label={copy.label}
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={copy.placeholder}
            />
          </label>
          <div className="dialogActions">
            <button className="secondaryButton" type="button" onClick={onCancel}>
              Cancel
            </button>
            <button className="primaryButton" type="submit" disabled={!trimmedName}>
              Create
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}
