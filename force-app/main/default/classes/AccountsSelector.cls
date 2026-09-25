/** Selector: the only place Account SOQL for this module lives. Runs in user mode. */
public inherited sharing class AccountsSelector implements IAccountsSelector {
    public List<Account> selectByIds(Set<Id> accountIds) {
        return [
            SELECT Id, Name, BillingCountry, BillingStreet, Industry, Type
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ];
    }
}
