const ENTRY_ROUTES = new Set(["/", "/login"]);

const normalizePathname = (pathname: string): string => {
  const trimmed = pathname.trim();

  if (!trimmed) {
    return "/";
  }

  if (trimmed.length > 1 && trimmed.endsWith("/")) {
    return trimmed.replace(/\/+$/, "");
  }

  return trimmed;
};

export const resolveLogoutRedirect = (pathname: string): string | null => {
  const normalizedPath = normalizePathname(pathname);

  return ENTRY_ROUTES.has(normalizedPath) ? null : "/login";
};
