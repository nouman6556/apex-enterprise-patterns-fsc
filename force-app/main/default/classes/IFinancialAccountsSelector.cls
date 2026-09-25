public interface IFinancialAccountsSelector {
    List<Financial_Account__c> selectByAccountIds(Set<Id> accountIds);
}
