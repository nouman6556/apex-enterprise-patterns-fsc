public interface IAccountsSelector {
    List<Account> selectByIds(Set<Id> accountIds);
}
