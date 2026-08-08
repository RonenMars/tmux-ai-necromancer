import * as React from 'react';

/** Base dark surface panel — hairline border, flat, subtle elevation. */
export interface CardProps {
  /** Border accent. @default "none" */
  accent?: 'none' | 'green' | 'azure';
  /** Apply the green reanimation glow. @default false */
  glow?: boolean;
  /** Lift + glow on hover. @default false */
  interactive?: boolean;
  padding?: string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function Card(props: CardProps): JSX.Element;
