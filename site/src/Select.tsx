// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

/** A labelled drop-down of `options`, pairs of value and text. */
export function Select({ label, value, options, onChange }: { label: string; value: string | number; options: [string | number, string][]; onChange: (value: never) => void }) {
  return (
    <label className="grid gap-1">
      <span className="label">{label}</span>
      <select className="rounded-[14px] border-2 border-ink bg-paper px-3 py-1.5" value={value}
        onChange={(event) => { const raw = event.target.value; const numeric = Number(raw); onChange((Number.isNaN(numeric) ? raw : numeric) as never); }}>
        {options.map(([key, text]) => <option key={key} value={key}>{text}</option>)}
      </select>
    </label>
  );
}
