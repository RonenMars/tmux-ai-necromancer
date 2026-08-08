import * as React from 'react';

/** Marketing feature tile: icon, title, description. Composes Card. */
export interface FeatureCardProps {
  /** Icon node (e.g. a Lucide <i data-lucide="...">). */
  icon?: React.ReactNode;
  title: string;
  /** @default "green" */
  accent?: 'green' | 'azure';
  /** @default "left" */
  align?: 'left' | 'center';
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function FeatureCard(props: FeatureCardProps): JSX.Element;
