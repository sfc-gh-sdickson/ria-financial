/*=============================================================================
  Ria Financial Intelligence Agent
  Step 1: Database, Schemas, and Warehouse Setup

  Execution Order: 1 of 9
  Description: Replaces the RIA_FINANCIAL_INTELLIGENCE database with RAW,
               ANALYTICS and ML schemas, plus the RIA_FINANCIAL_WH warehouse.
               WARNING: CREATE OR REPLACE DATABASE drops the previous build.
=============================================================================*/

CREATE OR REPLACE DATABASE RIA_FINANCIAL_INTELLIGENCE
    COMMENT = 'Ria Financial Intelligence: cross-border money transfer fraud, AML/sanctions compliance, KYC and Customer 360. All data is synthetic';
USE DATABASE RIA_FINANCIAL_INTELLIGENCE;

CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Raw layer: senders, beneficiaries, transfers, agent network, digital sessions, funding sources, alerts, cases, disputes, screening, SAR/CTR, KYC and Customer 360 source tables';

CREATE SCHEMA IF NOT EXISTS ANALYTICS
    COMMENT = 'Analytical layer: masked views, ML feature views, ML score tables, semantic views, Cortex Search services and agent functions';

CREATE SCHEMA IF NOT EXISTS ML
    COMMENT = 'Snowflake Model Registry and MODEL_REGISTRY (SR 11-7 model inventory) for the 10 Ria fraud models';

CREATE OR REPLACE WAREHOUSE RIA_FINANCIAL_WH WITH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for Ria Financial Intelligence Agent';

USE WAREHOUSE RIA_FINANCIAL_WH;
USE SCHEMA RAW;
