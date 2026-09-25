/**
 * Minimal unit of work.
 *  - Collects inserts, updates and deletes during a service call
 *  - Commits them in a fixed parent-to-child SObjectType order (deletes in reverse)
 *  - Resolves parent Ids for records registered against not-yet-inserted parents
 *  - Wraps everything in a savepoint: all DML succeeds or none does
 */
public inherited sharing class UnitOfWork implements IUnitOfWork {

    private final List<Schema.SObjectType> commitOrder;
    private final System.AccessLevel accessLevel;
    private final Map<Schema.SObjectType, List<SObject>> newRecords = new Map<Schema.SObjectType, List<SObject>>();
    private final Map<Schema.SObjectType, Map<Id, SObject>> dirtyRecords = new Map<Schema.SObjectType, Map<Id, SObject>>();
    private final Map<Schema.SObjectType, Map<Id, SObject>> deletedRecords = new Map<Schema.SObjectType, Map<Id, SObject>>();
    private final List<Relationship> relationships = new List<Relationship>();

    private class Relationship {
        SObject record;
        Schema.SObjectField field;
        SObject parent;
        Relationship(SObject record, Schema.SObjectField field, SObject parent) {
            this.record = record;
            this.field = field;
            this.parent = parent;
        }
    }

    public UnitOfWork(List<Schema.SObjectType> commitOrder) {
        this(commitOrder, System.AccessLevel.USER_MODE);
    }

    public UnitOfWork(List<Schema.SObjectType> commitOrder, System.AccessLevel accessLevel) {
        this.commitOrder = commitOrder;
        this.accessLevel = accessLevel;
        for (Schema.SObjectType t : commitOrder) {
            newRecords.put(t, new List<SObject>());
            dirtyRecords.put(t, new Map<Id, SObject>());
            deletedRecords.put(t, new Map<Id, SObject>());
        }
    }

    public void registerNew(SObject record) {
        if (record.Id != null) {
            throw new UnitOfWorkException('registerNew called with a record that already has an Id');
        }
        newRecords.get(typeOf(record)).add(record);
    }

    public void registerNew(SObject record, Schema.SObjectField relatedToField, SObject relatedTo) {
        registerNew(record);
        relationships.add(new Relationship(record, relatedToField, relatedTo));
    }

    public void registerDirty(SObject record) {
        requireId(record);
        dirtyRecords.get(typeOf(record)).put(record.Id, record);
    }

    public void registerDeleted(SObject record) {
        requireId(record);
        deletedRecords.get(typeOf(record)).put(record.Id, record);
    }

    public void commitWork() {
        Savepoint sp = Database.setSavepoint();
        try {
            for (Schema.SObjectType t : commitOrder) {
                resolveRelationships(t);
                if (!newRecords.get(t).isEmpty()) {
                    Database.insert(newRecords.get(t), true, accessLevel); // NOPMD - one DML per SObjectType by design; CRUD/FLS enforced via accessLevel (USER_MODE default)
                }
            }
            for (Schema.SObjectType t : commitOrder) {
                if (!dirtyRecords.get(t).isEmpty()) {
                    Database.update(dirtyRecords.get(t).values(), true, accessLevel); // NOPMD - one DML per SObjectType by design; CRUD/FLS enforced via accessLevel (USER_MODE default)
                }
            }
            for (Integer i = commitOrder.size() - 1; i >= 0; i--) {
                Map<Id, SObject> toDelete = deletedRecords.get(commitOrder[i]);
                if (!toDelete.isEmpty()) {
                    Database.delete(toDelete.values(), true, accessLevel); // NOPMD - one DML per SObjectType by design; CRUD/FLS enforced via accessLevel (USER_MODE default)
                }
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw new UnitOfWorkException('Unit of work rolled back: ' + e.getMessage(), e);
        }
    }

    private void resolveRelationships(Schema.SObjectType childType) {
        for (Relationship r : relationships) {
            if (r.record.getSObjectType() == childType) {
                r.record.put(r.field, r.parent.Id);
            }
        }
    }

    private Schema.SObjectType typeOf(SObject record) {
        Schema.SObjectType t = record.getSObjectType();
        if (!newRecords.containsKey(t)) {
            throw new UnitOfWorkException('SObjectType ' + t + ' is not registered with this unit of work');
        }
        return t;
    }

    private static void requireId(SObject record) {
        if (record.Id == null) {
            throw new UnitOfWorkException('Record must have an Id to be registered as dirty or deleted');
        }
    }
}
