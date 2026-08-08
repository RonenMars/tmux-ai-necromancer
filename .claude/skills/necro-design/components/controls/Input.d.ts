import * as React from 'react';

/** Terminal-flavored text input with optional prompt glyph and label. */
export interface InputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'style'> {
  label?: string;
  /** Show a leading prompt glyph. @default false */
  prompt?: boolean;
  /** Glyph shown when prompt is true. @default "›" */
  prefixGlyph?: string;
  invalid?: boolean;
  style?: React.CSSProperties;
  containerStyle?: React.CSSProperties;
}

export function Input(props: InputProps): JSX.Element;
