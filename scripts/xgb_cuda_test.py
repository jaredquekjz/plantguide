import sys, numpy as np
try:
    import xgboost as xgb
    print('xgboost', xgb.__version__)
    X = np.random.randn(200, 20).astype('float32')
    y = np.random.randn(200).astype('float32')
    print('[test] trying device=cuda …', flush=True)
    try:
        m = xgb.XGBRegressor(n_estimators=10, tree_method='hist', device='cuda')
        m.fit(X, y)
        print('[OK] trained on CUDA', flush=True)
    except Exception as e:
        print('[warn] CUDA path failed:', type(e).__name__, e, flush=True)
        print('[test] falling back to device=cpu …', flush=True)
        m = xgb.XGBRegressor(n_estimators=10, tree_method='hist', device='cpu')
        m.fit(X, y)
        print('[OK] trained on CPU', flush=True)
except Exception as e:
    print('[error] import or training failed:', type(e).__name__, e, file=sys.stderr)
    sys.exit(1)
