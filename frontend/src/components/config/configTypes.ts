import type { AppConfig } from '@/types';

export interface OAuthStatusResponse {
  installed: boolean;
  authenticated: boolean;
  message: string;
}

export interface ConfigSectionProps {
  config: AppConfig;
  val: (key: string) => string;
  checked: (key: string) => boolean;
  handleChange: (name: string, value: string | boolean) => void;
}
