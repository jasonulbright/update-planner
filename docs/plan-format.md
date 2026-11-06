# Plan file format (Suite ring plan)

Update Planner writes its plan as a Suite ring plan, version 1. The file has the fields of a Deployment Helper ring plan (`Rings\<name>.json`) and some extra fields. Deployment Helper loads the file as a ring plan and ignores the extra fields. The schema is [schema/ring-plan.schema.json](schema/ring-plan.schema.json). The same schema and the same test file are in the Deployment Helper repository.

## Fields

| Field | Content |
|---|---|
| `Format` | Always `SuiteRingPlan`. Extra. |
| `SchemaVersion` | Always `1`. Extra. |
| `Name`, `Description`, `HoldLaterRings`, `TimeBasedOn` | Deployment Helper plan fields. `Name` is `UpdatePlanner-<PlanId>`. |
| `Rings[]` | One ring is one wave, in wave order. |
| `Rings[].Name`, `CollectionID`, `CollectionName` | The wave name and its collection. |
| `Rings[].Purpose` | Always `Required`. |
| `Rings[].AvailableOffsetDays`, `DeadlineOffsetDays` | Days from the plan start date to the wave start and to the wave deadline. |
| `Rings[].UserNotification`, `OverrideServiceWindow`, `RebootOutsideServiceWindow`, `AllowMeteredConnection`, `DPGroup`, `SuccessThresholdPercent` | Deployment Helper ring fields with the defaults of the Deploy step. |
| `Rings[].MemberCount`, `MaintenanceWindows`, `StartDate`, `DeadlineDate` | Extra. Information for the review. |
| `Rings[].Updates[]` | Extra. The planned updates of the wave: `Sequence`, `CIId`, `ArticleId`, `Title`, `Severity`, `SeverityName`, `NeededDevices`. |
| `UpdatePlanner` | Extra. `PlanId`, `GeneratedAt`, `ComputerName`, `SiteCode`, `Parameters`, `Summary`, `Sync`, `Wsus`, `Skipped[]`. |

## Rules for Deployment Helper

Deployment Helper refuses a plan when a ring deadline is not later than its start, or not later than the deadline of the ring before. Set **Days to deadline** to 1 or more and **Days between waves** to 1 or more when you plan to load the file in Deployment Helper.

## Compatibility

A reader must ignore fields that it does not know. A change that removes or renames a field raises `SchemaVersion`. Update Planner reads only version 1.
