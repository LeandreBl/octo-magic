/** Returns an error message, or null when the value is valid. */
type Validator = (value: string) => string | null;

const isInt: Validator = (value) =>
  /^\d+$/.test(value) ? null : `expected an integer, got "${value}"`;

const isUrl: Validator = (value) => {
  try {
    new URL(value);
    return null;
  } catch {
    return `expected a URL, got "${value}"`;
  }
};

type EnvVarSpec = {
  description: string;
  /** Startup fails when a required var is missing or empty. */
  required?: boolean;
  /** Applied (and written back to process.env) when the var is unset. */
  default?: string;
  validate?: Validator;
};

const ENV_SPEC: Record<string, EnvVarSpec> = {
  DATABASE_URL: {
    description:
      "PostgreSQL connection string, e.g. postgresql://octo:pass@localhost:5432/octo " +
      "(assembled by docker/start.sh in the container)",
    required: true,
    validate: isUrl,
  },
  PORT: {
    description: "HTTP port of the API and the web game",
    default: "8080",
    validate: isInt,
  },
  NODE_ENV: {
    description: "Runtime environment",
    default: "development",
  },
  FIREBASE_PROJECT_ID: {
    description:
      "Firebase project of the logins: console → Project settings → General " +
      "→ Project ID. Verifying ID tokens needs no service account",
    required: true,
  },
  FIREBASE_API_KEY: {
    description:
      "Firebase Web API key (same page), handed to the game for the " +
      "email/password login: it is public, it ships in every client",
    required: true,
  },
  FORGE_URL: {
    description: "Base URL of the forge (server/forge.py); unset: no forge",
    validate: isUrl,
  },
  FORGE_EMAILS: {
    description:
      "Comma-separated emails of the only accounts allowed to forge, while " +
      "the forge runs on the owner's Claude subscription; unset: every " +
      "logged-in player",
  },
  WEB_DIR: {
    description: "Directory of the game's web export, served on /",
  },
  TURN_URL: {
    description:
      "Public address of the TURN server of the coop, e.g. " +
      "turn:octo-magic.turn.notdotio.com:3478; unset: STUN only",
  },
  TURN_SECRET: {
    description:
      "Secret shared with coturn (--static-auth-secret), signing the " +
      "time-limited TURN credentials — generate with: openssl rand -hex 32",
  },
};

/**
 * Validates the environment against ENV_SPEC: applies defaults, enforces
 * required vars and runs per-var validators. Startup fails with a message
 * listing every problem at once. Passed to ConfigModule.forRoot({ validate }).
 */
export function validateEnv(
  config: Record<string, unknown>,
): Record<string, unknown> {
  const errors: string[] = [];

  for (const [name, spec] of Object.entries(ENV_SPEC)) {
    let value = String(config[name] ?? "").trim();

    if (!value && spec.default !== undefined) {
      value = spec.default;
      config[name] = value;
      process.env[name] = value;
    }

    if (!value) {
      if (spec.required) {
        errors.push(`${name} is required — ${spec.description}`);
      }
      continue;
    }

    const error = spec.validate?.(value);
    if (error) {
      errors.push(`${name}: ${error} — ${spec.description}`);
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Invalid environment configuration:\n- ${errors.join("\n- ")}\n` +
        "See example.env for documentation.",
    );
  }

  return config;
}
