import * as React from 'react';

/**
 * Primary action control. Green = primary/alive, azure = secondary,
 * ghost = low-emphasis, danger = destructive.
 *
 * @startingPoint section="Controls" subtitle="Button — all variants & sizes" viewport="700x180"
 */
export interface ButtonProps {
  /** Visual emphasis. @default "primary" */
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
  /** @default "md" */
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  /** Add the signature reanimation glow. @default false */
  glow?: boolean;
  iconLeft?: React.ReactNode;
  iconRight?: React.ReactNode;
  type?: 'button' | 'submit' | 'reset';
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

export function Button(props: ButtonProps): JSX.Element;
