import csv
import math
import random
import statistics
from argparse import ArgumentParser
from pathlib import Path

def sigmoid(value):
    return 1.0 / (1.0 + math.exp(-max(-40.0, min(40.0, value))))

def solve(matrix, vector):
    augmented = [row[:] + [value] for row, value in zip(matrix, vector)]
    n = len(vector)
    for j in range(n):
        pivot = max(range(j, n), key=lambda i: abs(augmented[i][j]))
        augmented[j], augmented[pivot] = augmented[pivot], augmented[j]
        row = augmented[j]
        divisor = row[j]
        for k in range(j, n + 1):
            row[k] /= divisor
        for i in range(j + 1, n):
            other_row = augmented[i]
            factor = other_row[j]
            for k in range(j, n + 1):
                other_row[k] -= factor * row[k]
    result = [0.0] * n
    for i in reversed(range(n)):
        result[i] = augmented[i][-1] - sum(
            augmented[i][j] * result[j] for j in range(i + 1, n)
        )
    return result

def get_features(row):
    paid = float(row['paid'])
    log_paid = math.log1p(max(0, paid))
    shares = [float(row[name]) / paid if paid > 0 else 0.0
              for name in ('ip_paid', 'op_paid', 'car_paid')]
    counts = [int(row[name]) for name in ('ip_count', 'op_count', 'carrier_count')]
    return (log_paid, *shares, *(math.log1p(n) for n in counts), float(counts[0] == 0))

def train(rows, spend_only=False, feature_extractor=get_features):
    predictors = [feature_extractor(row) for row in rows]
    if spend_only:
        predictors = [row[:1] for row in predictors]
    centers = [statistics.mean(col) for col in zip(*predictors)]
    scales = [statistics.pstdev(col) or 1.0 for col in zip(*predictors)]

    def transform(raw):
        return (1., *((x - m) / s for x, m, s in zip(raw, centers, scales)))

    x_values = [transform(row) for row in predictors]
    y_values = [int(row['subsequent_top']) for row in rows]
    dimension = len(x_values[0])
    beta = [0.] * dimension
    penalty = 5.
    for _ in range(20):
        gradient = [0.] * dimension
        hessian = [[0.] * dimension for _ in range(dimension)]
        for x, y in zip(x_values, y_values):
            probability = sigmoid(sum(a * b for a, b in zip(x, beta)))
            residual = y - probability
            weight = probability * (1 - probability)
            for j, value in enumerate(x):
                gradient[j] += residual * value
                wj = weight * value
                for k in range(j + 1):
                    hessian[j][k] += wj * x[k]
        for j in range(dimension):
            for k in range(j):
                hessian[k][j] = hessian[j][k]
            if j:
                hessian[j][j] += penalty
                gradient[j] -= penalty * beta[j]
        step = solve(hessian, gradient)
        beta = [x + dx for x, dx in zip(beta, step)]
        if max(map(abs, step)) < 1e-7:
            break
    else:
        raise RuntimeError('Model did not converge')
    return lambda row: sum(a * b for a, b in zip(beta, transform(feature_extractor(row))))

def summarize(spend, mixed, count):
    only_spend = set(spend[:count]) - set(mixed[:count])
    only_mixed = set(mixed[:count]) - set(spend[:count])
    return (sum(y for _, _, _, y in spend[:count]),
            sum(y for _, _, _, y in mixed[:count]),
            len(only_mixed),
            sum(y for _, _, _, y in only_spend),
            sum(y for _, _, _, y in only_mixed))

def bootstrap(rows, fraction):
    rng = random.Random(18342)
    n = len(rows)
    count = math.ceil(fraction * n)
    changes = []
    for _ in range(1000):
        sample = rng.choices(rows, k=n)
        spend = sorted(sample, key=lambda row: (-row[1], row[0]))
        mixed = sorted(sample, key=lambda row: (-row[2], row[0]))
        difference = sum(row[3] for row in mixed[:count]) - sum(row[3] for row in spend[:count])
        changes.append(100 * difference / count)
    changes.sort()
    return round(changes[24], 2), round(changes[974], 2)

def evaluate(data, scope, capacities, interval_at=None):
    training = [row for row in data if int(row['split_hash'][:2], 16) < 179]
    testing = [row for row in data if int(row['split_hash'][:2], 16) >= 179]
    score = train(training)
    spend_fit = train(training, spend_only=True)
    assert spend_fit({'paid': 12001, 'ip_paid': 1, 'op_paid': 1, 'car_paid': 1, 'ip_count': 0,
                      'op_count': 0, 'carrier_count': 0}) > spend_fit(
        {'paid': 12000, 'ip_paid': 1, 'op_paid': 1, 'car_paid': 1, 'ip_count': 0,
         'op_count': 0, 'carrier_count': 0})
    predictions = [(row['split_hash'], float(row['paid']), score(row), int(row['subsequent_top']))
                   for row in testing]
    print(scope, 'train', len(training), 'test', len(testing),
          'test positives', sum(row[3] for row in predictions), flush=True)
    spend = sorted(predictions, key=lambda row: (-row[1], row[0]))
    mixed = sorted(predictions, key=lambda row: (-row[2], row[0]))
    for fraction in capacities:
        count = math.ceil(fraction * len(testing))
        print(fraction, count, 'spend hits, mix hits, exclusive each, spend-only hits, mix-only hits',
              summarize(spend, mixed, count),
              'conditional bootstrap pp', bootstrap(predictions, fraction) if fraction == interval_at else None,
              flush=True)


def read_input(path):
    with path.open(newline='', encoding='utf-8') as file:
        data = list(csv.DictReader(file))
    assert len(data) == 63034
    assert len({row['split_hash'] for row in data}) == len(data)
    return data


if __name__ == '__main__':
    parser = ArgumentParser(description='Reproduce holdout and scope-sensitivity evaluations.')
    parser.add_argument('input_csv', type=Path)
    data = read_input(parser.parse_args().input_csv)
    top = [row for row in data if row['prior_top'] == '1']
    assert len(top) == 6368
    evaluate(top, 'Prior top decile', [0.10, 0.25, 0.50], 0.25)
    evaluate([row for row in top if row['esrd_flag'] == '0'],
             'Prior top decile, ESRD flag zero', [0.25], 0.25)
    evaluate(data, 'All paired beneficiaries', [0.05, 0.10, 0.20])
