/** Selector for Financial_Account__c. Runs in user mode. */
public inherited sharing class FinancialAccountsSelector implements IFinancialAccountsSelector {
    public List<Financial_Account__c> selectByAccountIds(Set<Id> accountIds) {
        return [
            SELECT Id, Account__c, Account_Number__c, Type__c, Balance__c, Status__c
            FROM Financial_Account__c
            WHERE Account__c IN :accountIds
            WITH USER_MODE
            ORDER BY Account__c
        ];
    }
}
