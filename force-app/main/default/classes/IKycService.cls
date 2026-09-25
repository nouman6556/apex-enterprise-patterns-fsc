public interface IKycService {
    List<KycService.KycResult> verify(Set<Id> accountIds);
}
