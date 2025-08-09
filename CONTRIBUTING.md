# Contributing to AWSSQLHA

Thank you for your interest in contributing to the SQL Server 2022 FCI High Availability automation project!

## How to Contribute

### Reporting Issues
- Use the GitHub Issues tab to report bugs or request features
- Include detailed information about your environment
- Provide steps to reproduce any issues
- Include relevant error messages and logs

### Code Contributions
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes following the coding standards below
4. Test your changes thoroughly
5. Commit your changes (`git commit -m 'Add some amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Coding Standards

### PowerShell Guidelines
- Use PowerShell best practices and approved verbs
- Include comprehensive error handling with try/catch blocks
- Add inline comments for complex logic
- Use proper parameter validation
- Follow the existing module structure

### Documentation
- Update README.md for any significant changes
- Document new functions with comment-based help
- Update TODO.md with completed items
- Add new features to FUTURE.md if they inspire additional ideas

### Testing
- Test all changes in a development environment
- Ensure idempotent behavior (safe to re-run)
- Validate against the requirements in REQUIREMENTS.md
- Test failover scenarios where applicable

## Development Environment
- Windows Server 2019 or 2022
- PowerShell 5.1 or PowerShell 7+
- AWS CLI v2
- Access to AWS environment for testing
- SQL Server 2022 media for full testing

## Questions?
Feel free to open an issue for questions about contributing or reach out to the maintainers.
