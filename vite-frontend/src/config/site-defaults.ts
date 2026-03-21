export type DefaultSiteConfig = {
  name: string;
  version: string;
  app_version: string;
  github_repo: string;
  app_logo: string;
  app_favicon: string;
};

export const createDefaultSiteConfig = (): DefaultSiteConfig => ({
  name: "RealmFlow",
  version:
    (import.meta as ImportMeta & { env?: { VITE_APP_VERSION?: string } }).env
      ?.VITE_APP_VERSION || "dev",
  app_version: "1.0.3",
  github_repo: "https://github.com/JackLuo1980/realm-flow",
  app_logo: "",
  app_favicon: "",
});
