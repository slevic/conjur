# Authenticators Management Improvement Proposal

- [Authenticators Management Improvement Proposal](#authenticators-management-improvement-proposal)
  - [Introduction](#introduction)
  - [Proposed Solution](#proposed-solution)
    - [Add Authenticator](#add-authenticator)
      - [Functionality](#functionality)
      - [Synopsis](#synopsis)
      - [Example](#example)
    - [Delete Authenticator](#delete-authenticator)
      - [Functionality](#functionality-1)
      - [Synopsis](#synopsis-1)
      - [Example](#example-1)
    - [Update Authenticator](#update-authenticator)
      - [Functionality](#functionality-2)
      - [Synopsis](#synopsis-2)
      - [Example](#example-2)
    - [Enable Authenticator](#enable-authenticator)
      - [Functionality](#functionality-3)
      - [Synopsis](#synopsis-3)
      - [Example](#example-3)
    - [Disable Authenticator](#disable-authenticator)
      - [Functionality](#functionality-4)
      - [Synopsis](#synopsis-4)
      - [Example](#example-4)
  - [Backwards Compatibility](#backwards-compatibility)
  - [Performance](#performance)
  - [Security](#security)
  - [Documentation](#documentation)
  - [Implementation Options](#implementation-options)
    - [Alternative 1 - Server Side](#alternative-1---server-side)
      - [Pros](#pros)
      - [Cons](#cons)
    - [Alternative 2 - CLI Side](#alternative-2---cli-side)
      - [Pros](#pros-1)
      - [Cons](#cons-1)
  - [Version Update](#version-update)
  - [Delivery Plan](#delivery-plan)
  - [Recommendation](#recommendation)
  
## Introduction

Conjur authenticators are defined as sub-policies, under the `conjur` policy.  
Currently to define an authenticator, the user needs to complete the following steps:

- Read the documentation
- Understand how the authenticator policy is structured
- Create a policy yaml file that defines the authenticator
- Load the policy using Conjur CLI
- Fill the authenticator policy variables with their values
- Enable the authenticator through an environment variable or REST API call

To delete an authenticator, the user needs to complete these steps.  
Either:

- Create a policy with a `- !delete` statement, on the authenticator policy
- Load the policy using Conjur CLI

Or:

- Update the `conjur` policy yaml file and take out the authenticator
- Reload the `conjur` policy using the `--replace` option  

The current user experience requires a certain level of expertise. The user needs to understand the policy structure of each authenticator and the process is comprised of multiple steps. This proposal offers an easier way for managing authenticators.

## Proposed Solution

The proposed solution is to add a few simple Conjur CLI commands (and possibly APIs, see two alternatives below), that would hide the complexity and provide a single step to perform each action:

### Add Authenticator

#### Functionality

Defines a new authenticator in Conjur. Behind the scenes, this command will creat the authenticator policy and fill it with all its required data. If the data is not required to be given by the user, like the `authn-k8s` CA cert and key, the information will be generated automatically.

#### Synopsis

conjur config authenticator add *authenticator-type/service-id* [*parameters*]

#### Example

```shell script
$ conjur config authenticator add authn-oidc/my-idp --provider-uri my-uri --id-token-user-property prop
```

### Delete Authenticator

#### Functionality

Deletes an existing authenticator in Conjur. Deletes the authenticator policy and deletes the authenticator from the enabled/disabled authenticators list.

#### Synopsis

conjur config authenticator delete *authenticator-type/service-id*

#### Example

```shell script
$ conjur config authenticator delete authn-oidc/my-idp
```

### Update Authenticator

#### Functionality

Updates an existing authenticator in Conjur. Updates the authenticator variables.

#### Synopsis

conjur config authenticator update *authenticator-type/service-id* [*parameters*]

#### Example

```shell script
$ conjur config authenticator update authn-oidc/my-idp --provider-uri new-uri
```

### Enable Authenticator

#### Functionality

Enables an authenticator in the Conjur database (can be overriden by environment variable).

#### Synopsis

conjur config authenticator enable *authenticator-type/service-id*

#### Example

```shell script
$ conjur config authenticator enable authn-oidc/my-idp
```

### Disable Authenticator

#### Functionality

Disables an authenticator in the Conjur database (can be overriden by environment variable).

#### Synopsis

conjur config authenticator disable *authenticator-type/service-id*

#### Example

```shell script
$ conjur config authenticator disable authn-oidc/my-idp
```

## Backwards Compatibility

- The authenticators keep their same structure in Conjur. Users could still manage them in the way it's done today.  
- These CLI commands are uniting policy loads and variable updates into a single step, therefore running the commands requires permissions to both load a policy under the `conjur` policy and to update the variables in that policy.

## Performance

The proposal only simplifies the steps, not adding or changing them, therefore the performance remain the same.

## Security

No security implications. These new CLI commands perform the same action, with an easier experience.

## Documentation

We will need to update the docs of every authenticator, to specify how to use the new CLI commands. In addition, we will need to add documentation for enabling/disabling authenticators.

## Implementation Options

### Alternative 1 - Server Side

The new functionality will be developed on the Conjur side. New APIs will be exposed for this new functionality. For example, in order to add an authenticator, the client will call a `POST` request to `/{authenticator-type}/{service-id}/{account}`. Example:

```shell script
curl --request POST \
  --data '{"providerUri": "my-uri", "id-token-user-property": "prop"}' \
  https://conjur.mycompany.net/authn-oidc/my-authenticator/my-account
```

The CLI will use these new APIs. In order for the CLI to remain up to date with the authenticator types, their required parameters and optional parameters, Conjur will expose an internal API that would provide this authenticator schema information. This API will be called by the CLI whenever this information will be needed. For example, when running `conjur config authenticator add/update {authenticator-type}/{service-id} --help`.

#### Pros

- Reduces complexity on the client side. Any client can simply leverage the simplified UX, not just Conjur CLI.
- The feature is decoupled and sealed on the server side. Any change in the underlying infrastructure of the authenticators in the future, will not break the API for the client.

#### Cons

- The new functionality will only be supported from the latest Conjur version where this functionality is added.
- This solution requires more effort to develop.

### Alternative 2 - CLI Side

The new functionality will be developed on the Conjur CLI side. The CLI will interact with Conjur through the policy, variable and authenticator APIs.

#### Pros

- The solution would work with older Conjur versions. Users would be able to leverage the functionality from day one, without needing to update to the latest Conjur first.
- This solution requires less effort to develop.

#### Cons

- Increases complexity on the CLI side.
- Will force the user to work with the Conjur CLI in order to leverage the new functionality.
- Can potentially increase the technical debt if we chose to switch to another CLI tool.

## Version Update

Alternative 1 requires Conjur + CLI release.  
Alternative 2 requires only CLI release.

## Delivery Plan

High level delivery plan for **alternative 1** will include the following steps:

| Functionality                           | Dev    | Tests  |
|-----------------------------------------|--------|--------|
| Adding authenticators in Conjur         | 5 days | 3 days |
| Adding authenticators in CLI            | 2 days | 1 days |
| Deleting authenticators in Conjur       | 3 days | 2 days |
| Deleting authenticators in CLI          | 1 days | 1 days |
| Updating authenticators in Conjur       | 2 days | 2 days |
| Updating authenticators in CLI          | 1 days | 1 days |
| Enabling authenticators in CLI          | 1 days | 2 days |
| Disabling authenticators in CLI         | 1 days | 2 days |
| Adding Conjur authn schema internal API | 2 days | 2 days |
| Modify deployment examples              | 3 days | -      |
| Documentation                           | 2 days | -      |
  
**Total: 39 days**

High level delivery plan for **alternative 2** will include the following steps:

| Functionality                     | Dev    | Tests  |
|-----------------------------------|--------|--------|
| Adding authenticators in CLI      | 4 days | 2 days |
| Deleting authenticators in CLI    | 3 days | 2 days |
| Updating authenticators in CLI    | 2 days | 2 days |
| Enabling authenticators in CLI    | 1 days | 2 days |
| Disabling authenticators in CLI   | 1 days | 2 days |
| Modify deployment examples        | 3 days | -      |
| Documentation                     | 2 days | -      |
| Version update                    | 1 day  | -      |
  
**Total: 27 days**

## Recommendation

We should develop alternative 1 (server side). The busines logic of the product should be located on the server side and not on the client side. The effort difference is not significant, but the value it offers over alternative 2 is.
