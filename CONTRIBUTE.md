# CONTRIBUTING.md

## Contributing to Ticket City Smart Contract

Thank you for your interest in contributing to our Ticket City smart contract! This document provides guidelines for contributing to this project.

When contributing to this repository, please first discuss the change you wish to make via issue with the owners of this repository before making a change.

Please note we have a code of conduct, please follow it in all your interactions with the project.

## Development Environment Setup

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Solidity](https://docs.soliditylang.org/en/latest/installing-solidity.html)
- [Node.js](https://nodejs.org/) (v16 or later)

### Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:

```bash
git clone https://github.com/[YOUR-USERNAME]/[PROJECT-NAME].git
cd [PROJECT-NAME]
```

3. Install dependencies:

```bash
forge install
npm install
yarn install
```

4. Set up git hooks (optional):

```bash
pre-commit install
```

## Development Workflow

### Branching Strategy

- `main` - Production-ready code
- `Staging` - Latest development changes
- Feature branches - Named as `feature/[feature-name]`
- Bug fix branches - Named as `fix/[bug-name]`

### Making Changes

1. Create a new branch for your feature or bugfix:

```bash
git checkout -b feature/your-feature-name
```

2. Make your changes
3. Run tests to ensure your changes don't break existing functionality:

```bash
forge test
```

4. Format your code:

```bash
forge fmt
```

5. Run static analysis (optional):

```bash
slither .
```

6. Commit your changes with a descriptive message:

```bash
git commit -m "feat: description of your changes"
git commit -m "fix: description of your changes"
```
or follow this approach [https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13]

## Pull Requests

1. Push your changes to your fork:

```bash
git push origin feature/your-feature-name
```

2. Open a pull request against the `staging` branch
3. Ensure the PR description clearly describes the problem and solution
4. Tag @DevBigEazi in your PR description to notify the maintainer
5. Wait for review and address any feedback

## Coding Standards

### Solidity Style Guide

- Follow the [Solidity style guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use 4 spaces for indentation
- Maximum line length is 120 characters
- Use `@notice`, `@dev`, `@param`, and `@return` NatSpec comments for all functions

### Naming Conventions

- Contract names: PascalCase
- Function names: camelCase
- Variables: camelCase
- Constants: UPPER_CASE_WITH_UNDERSCORES
- Modifiers: camelCase
- Events: PascalCase

### Code Quality

- All code should be well-commented
- Write comprehensive unit tests for all functionality
- Aim for high test coverage
- Document complex logic with clear explanations

## Security Considerations

- Follow best practices outlined in the [Smart Contract Security Verification Standard](https://github.com/securing/SCSVS)
- Always consider gas optimization
- Be aware of common vulnerabilities (reentrancy, integer overflow, etc.)
- Document known security limitations

## Testing

- Write unit tests for all functionality
- Test edge cases thoroughly
- Include fuzzing tests where appropriate
- Gas optimization tests are encouraged

Run tests using:

```bash
forge test
```

For gas reporting:

```bash
forge test --gas-report
```

## Documentation

- Document all public functions
- Keep README up to date
- Update changelog for significant changes

## License

By contributing to this project, you agree that your contributions will be licensed under the project's license (see LICENSE file).

## Questions?

If you have any questions or need help, please open an issue or reach out to adesholatajudeen1@gmail.com.

---

Thank you for helping improve our Ticket City smart contract!
