public interface IUnitOfWork {
    void registerNew(SObject record);
    void registerNew(SObject record, Schema.SObjectField relatedToField, SObject relatedTo);
    void registerDirty(SObject record);
    void registerDeleted(SObject record);
    void commitWork();
}
