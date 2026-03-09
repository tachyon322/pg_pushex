# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of PgPushex
- Schema-first database migration DSL
- Automatic diff calculation between desired and current schema
- Interactive column rename detection
- Full transaction safety for all operations
- PostgreSQL-specific features support (enums, generated columns, extensions)
- Foreign key dependency resolution with topological sorting
- Mix tasks: `pg_pushex.push`, `pg_pushex.generate`, `pg_pushex.generate.full`, `pg_pushex.reset`
- Support for pgvector and citext extensions
- Generated columns with SQL fragment expressions
- Comprehensive documentation and guides

## [0.1.0] - 2025-03-09

### Added
- First public release
- Core schema DSL with `table`, `column`, `index`, `timestamps`, `extension`, `execute` macros
- PostgreSQL introspection from system catalogs
- SQL generation for all supported operations
- Migration file generation for Ecto compatibility
- CLI helpers for argument parsing and validation
- Interactive prompts for destructive operations

[Unreleased]: https://github.com/yourusername/pg_pushex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/pg_pushex/releases/tag/v0.1.0
