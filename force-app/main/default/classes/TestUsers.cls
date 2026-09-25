/** Creates a least-privilege test user with a permission set, avoiding mixed-DML issues. */
@IsTest
public class TestUsers {
    public static User withPermissionSet(String permissionSetName) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '') + Datetime.now().getTime();
            u = new User(
                ProfileId = p.Id, LastName = 'Synthetic Tester', Alias = 'stest',
                Email = 'tester@example.com', Username = 'tester' + unique + '@example.com',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Chicago'
            );
            insert u;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }
}
