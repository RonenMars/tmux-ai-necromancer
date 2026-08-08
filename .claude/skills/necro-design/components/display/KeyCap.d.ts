import * as React from 'react';

/** A single keyboard keycap, terminal-styled. */
export interface KeyCapProps {
  /** @default "neutral" */
  tone?: 'neutral' | 'green' | 'azure';
  /** @default "md" */
  size?: 'sm' | 'md' | 'lg';
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function KeyCap(props: KeyCapProps): JSX.Element;

export interface KeyComboProps {
  /** Ordered keycaps joined by "+". */
  keys: Array<{ label: string; tone?: 'neutral' | 'green' | 'azure' }>;
  size?: 'sm' | 'md' | 'lg';
  style?: React.CSSProperties;
}
export function KeyCombo(props: KeyComboProps): JSX.Element;
