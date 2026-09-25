trigger FinancialAccountTrigger on Financial_Account__c (before insert, before update) {
    FinancialAccounts domain = new FinancialAccounts(Trigger.new);
    if (Trigger.isInsert) {
        domain.onBeforeInsert();
    } else {
        domain.onBeforeUpdate();
    }
}
