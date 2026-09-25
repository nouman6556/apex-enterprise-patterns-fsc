/**
 * Processes large KYC runs in chunks: each job verifies one chunk and
 * enqueues the next job with the remainder, keeping every transaction
 * well inside governor limits.
 */
public with sharing class KycVerificationQueueable implements Queueable {

    public static final Integer DEFAULT_CHUNK_SIZE = 200;
    private final List<Id> pending;
    private final Integer chunkSize;

    public KycVerificationQueueable(List<Id> accountIds) {
        this(accountIds, DEFAULT_CHUNK_SIZE);
    }

    public KycVerificationQueueable(List<Id> accountIds, Integer chunkSize) {
        this.pending = new List<Id>(accountIds);
        this.chunkSize = chunkSize;
    }

    public void execute(QueueableContext context) {
        Set<Id> chunk = new Set<Id>();
        List<Id> remainder = new List<Id>();
        for (Integer i = 0; i < pending.size(); i++) {
            if (i < chunkSize) { chunk.add(pending[i]); } else { remainder.add(pending[i]); }
        }
        if (!chunk.isEmpty()) {
            ((IKycService) Application.get(IKycService.class)).verify(chunk);
        }
        // Chained enqueues are not allowed inside Apex tests.
        if (!remainder.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new KycVerificationQueueable(remainder, chunkSize));
        }
    }

    @TestVisible
    private Integer pendingCount() {
        return pending.size();
    }
}
