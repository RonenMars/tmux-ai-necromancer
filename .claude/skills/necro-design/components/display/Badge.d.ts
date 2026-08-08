import * as React from 'react';

/**
 * Compact status chip mapped to the brand's lifecycle states.
 *
 * @startingPoint section="Display" subtitle="Status badges & keybinding caps" viewport="700x150"
 */
export interface BadgeProps {
  /** @default "alive" */
  tone?: 'alive' | 'data' | 'dead' | 'dormant';
  /** Show a leading status dot. @default false */
  dot?: boolean;
  /** Pulse the dot (for live/restoring states). @default false */
  pulse?: boolean;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}

export function Badge(props: BadgeProps): JSX.Element;
