/**
 * Nightly re-verification of every Account that holds an active financial
 * account. Schedule with:
 *   System.schedule('KYC re-verification', '0 0 2 * * ?', new KycReverificationBatch());
 */
public with sharing class KycReverificationBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM Account
            WHERE Id IN (SELECT Account__c FROM Financial_Account__c WHERE Status__c = 'Active')
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        ((IKycService) Application.get(IKycService.class)).verify(new Map<Id, Account>(scope).keySet());
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'KYC re-verification batch finished: ' + bc.getJobId());
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new KycReverificationBatch(), 200);
    }
}
