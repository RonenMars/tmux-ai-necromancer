import * as React from 'react';

/**
 * The signature surface — a terminal window with macOS chrome and a near-black
 * monospace body. Use for hero, code demos, and any "live session" UI.
 *
 * @startingPoint section="Surfaces" subtitle="Terminal window, cards & feature tiles" viewport="700x400"
 */
export interface TerminalWindowProps {
  title?: string;
  /** Hero reanimation glow. @default false */
  glow?: boolean;
  /** Left status-bar text (tmux-style). */
  statusLeft?: string;
  /** Right status-bar text. */
  statusRight?: string;
  bodyStyle?: React.CSSProperties;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function TerminalWindow(props: TerminalWindowProps): JSX.Element;
