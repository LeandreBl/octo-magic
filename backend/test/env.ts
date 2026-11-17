// Imported first by the tests, before the app reads its environment.
process.env.NODE_ENV = "test";
process.env.DATABASE_URL = "postgresql://unused@localhost/unused";
process.env.FIREBASE_PROJECT_ID = "test";
process.env.FIREBASE_API_KEY = "k";
delete process.env.FORGE_URL;
delete process.env.TURN_URL;
