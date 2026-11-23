# Estimated AWS monthly cost (proposed production design, eu-central-1)

**These are order-of-magnitude estimates from memory of public list prices, not a quote.** I could not query live AWS pricing. Verify with the AWS Pricing Calculator before use. Nothing in this repo was deployed to AWS, so actual cost to date is **$0**.

Assumptions: 730 h/month, on-demand, 2 AZs, modest traffic (<1 TB egress), SQL Server licence included.

| Item | Sizing | Approx. USD/month |
|---|---|---|
| RDS SQL Server Web, Multi-AZ | db.t3.xlarge, 100 GB gp3 | 600–900 (largest driver) |
| Search tier | 2 × ~2 vCPU/8 GB nodes (Elastic Cloud or ECS/EC2) | 200–350 |
| Fargate platform | 2 tasks × 2 vCPU/4 GB | ~145 |
| Fargate storefront | 2 tasks × 1 vCPU/2 GB | ~70 |
| NAT gateways | 2 (one per AZ) + data | 80–110 |
| ALB | 1 + LCUs | 25–40 |
| ElastiCache Redis | 2 × cache.t4g.small | ~50 |
| CloudWatch, S3, Secrets, ECR, Route 53 | | 30–60 |
| **Total** | | **≈ 1,200–1,800** |

Levers: single-AZ RDS and one NAT for non-prod (halves cost); RDS SQL Server Express/Developer is not allowed in production; Savings Plans for Fargate; VPC endpoints instead of NAT for ECR/S3/Logs/Secrets; PostgreSQL instead of SQL Server **only if** the chosen Platform version supports it (removes licence cost; needs validation). A dev environment of ~$300–500/month is realistic.
