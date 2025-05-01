EXchange Open Source Platform
===========================

Plxtra XOSP (EXchange Open Source Platform) is a complete distribution of the [Plxtra](https://plxtra.org) software suite, providing a full retail trading platform and digital exchange for the purposes of demonstration, evaluation, and development.

This repository contains the distribution's installation scripts and configuration.

## Philosophy

XOSP is a example, a platform to build upon. It provides a full retail trading platform and digital exchange for the purposes of demonstration, evaluation, and development.

XOSP is intended to be fully open-source, from the container runtime, to each service, application, and dependencies, to the installation routines. We're not quite there yet, but as more of the platform code is released, XOSP becomes more complete.

XOSP is a beginning, a starting point to build more editions of Plxtra upon. Different configurations for eg: cloud installs, redundant scenarios, third-party exchange integrations.

## Audience

XOSP is intended for companies and individuals wanting to get started with running a digital exchange, or provide retail services to an existing third-party exchange as a broker.

This specific repository provides a pre-configured distribution of Plxtra, where developers and technically-minded individuals can deploy a full suite of components for testing, demonstration, or development purposes. It offers a number of customisable points that can be manipulated.

## Platform Scope

Plxtra is focused on offering a flexible retail trading platform solution. While user authentication and customer management are essential parts of a complete business solution, the purpose of Plxtra is not in providing secure user authentication, CRM, or other administrative back-office systems. Instead, Plxtra offers integration points for third-party components to fill these roles.

XOSP utilises these integration points, providing a suite of scripts to perform common system administration tasks. These are intended as a starting point, demonstrating usage of the system APIs.

### Authentication

XOSP includes a rudimentary OAuth and OIDC-compliant authentication server through the [OpenIddict](https://openiddict.com/) project. This is sufficient for development and demonstration purposes, however it is not sufficient for a production system. Instead, Plxtra offers compatibility with existing off-the-shelf SSO solutions such as:

- [Auth0](https://www.auth0.com/)
- [Identity Server](https://www.identityserver.com/)

### Customer Relationship Management

Plxtra follows the philosophy of minimum opinionation in regards to customer data. There are users who login, there are accounts that can be traded, and outside of those concepts Plxtra doesn't get involved. How logins are registered, what information they hold, how permissions are decided upon, and what support tasks are required, is too specific to any one business.

Rather than try to provide a one-size-fits-all solution, which is a vast undertaking that would take away from the focus of Plxtra, it offers a suite of APIs with REST, GraphQL, and WebSocket streaming for feeding this data into and out of the system, and to allow easy realtime manipulation.

### Back Office

As with a CRM, Plxtra does not provide a solution for back-office tasks such as settling of funds, business reporting, or other highly business-specific tasks.

Instead, Plxtra offers APIs and integration points to enable these business tasks.
